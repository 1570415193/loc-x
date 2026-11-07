import argparse
import hashlib
from contextlib import closing
from pathlib import Path
import os
import shutil
import sqlite3
import subprocess
import tempfile


root = Path(__file__).resolve().parent
target = ('AppleIssued', 'apple.com', '^gs-loc$|^gs-loc-cn$')


def contents(path):
    with closing(sqlite3.connect(f'{path.as_uri()}?mode=ro', uri=True)) as db:
        assert db.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
        return (
            db.execute('PRAGMA user_version').fetchone(),
            db.execute('SELECT * FROM admin ORDER BY key').fetchall(),
            db.execute('SELECT * FROM rules ORDER BY policyName,domainSuffix,labelRegex').fetchall(),
        )


def create_sample(path):
    with closing(sqlite3.connect(path)) as db, db:
        db.executescript('''
            PRAGMA user_version = 3;
            CREATE TABLE admin (key TEXT PRIMARY KEY, ival INTEGER, value BLOB);
            INSERT INTO admin VALUES ('version', 131, NULL);
            CREATE TABLE rules (
                policyName TEXT, domainSuffix TEXT, labelRegex TEXT,
                policies BLOB, transparentConnection INTEGER,
                UNIQUE (policyName, domainSuffix, labelRegex)
            );
        ''')
        db.executemany('INSERT INTO rules VALUES (?, ?, ?, ?, ?)', [
            (*target, bytes(1580), 0),
            ('AppleIssued', 'apple.com', '^other$', b'unrelated', 0),
            ('AppleIssued', 'example.com', target[2], b'unrelated', 0),
            ('OtherPolicy', 'apple.com', target[2], b'unrelated', 1),
        ])


parser = argparse.ArgumentParser(description='Test the rules helper on disposable SQLite files.')
parser.add_argument('--sample', type=Path, help='Optional local copy of an original v131 database')
args = parser.parse_args()
if os.geteuid() != 0:
    parser.error('Run with sudo to test the helper’s root-only entry point.')

with tempfile.TemporaryDirectory(prefix='wloc-helper-test-') as directory:
    temp = Path(directory)
    sample = args.sample.resolve(strict=True) if args.sample else temp / 'sample.sqlite3'
    if args.sample is None:
        create_sample(sample)
    live = temp / 'live.sqlite3'
    backup_base = temp / 'backup.sqlite3'
    backup = Path(str(backup_base) + '.content-131')
    binary = temp / 'tester'
    sdk = root / os.environ.get('WLOC_SDK', '../ios-sdks/iPhoneOS15.6.sdk')
    header = sdk / 'usr/include/sqlite3.h'
    if header.is_file():
        shutil.copyfile(header, temp / 'sqlite3.h')
    harness = temp / 'harness.c'
    harness.write_text('#include "rules.h"\nint main(int argc,char **argv){return argc==2?run_rules_command(argv[1]):64;}\n')
    subprocess.run(['gcc','-std=gnu11','-Wall','-Wextra','-Werror','-I',str(root),'-I',str(temp),
                    f'-DWLOC_LIVE_DB="{live}"', f'-DWLOC_BACKUP_DB="{backup_base}"', '-DWLOC_TEST_SCOPE="fixture-device/os"',
                    str(harness), str(root / 'rules.c'), '-l:libsqlite3.so.0', '-o', str(binary)], check=True)
    baseline = contents(sample)
    expected = baseline[:2] + ([row for row in baseline[2] if row[:3] != target],)
    assert len(baseline[2]) - len(expected[2]) == 1, 'Sample must contain exactly one target rule'

    def run(command, want=0, **kwargs):
        result = subprocess.run([binary, command], text=True, capture_output=True, timeout=12, **kwargs)
        assert result.returncode == want, (command, result.returncode, result.stdout, result.stderr)
        return result.stdout + result.stderr

    def reset():
        if backup.exists() or backup.is_symlink():
            backup.unlink()
        shutil.copyfile(sample, live)
        os.chmod(live, 0o600)

    reset()
    attrs = live.stat()
    assert 'present' in run('check') and not backup.exists()
    run('apply')
    assert contents(live) == expected and contents(backup) == baseline
    assert live.stat().st_mode == attrs.st_mode and live.stat().st_ino == attrs.st_ino
    assert 'absent' in run('check')
    assert 'already absent' in run('apply')
    run('restore')
    assert contents(live) == baseline
    assert 'already present' in run('restore')
    run('apply')
    run('restore')
    assert contents(live) == baseline
    print('PASS read-only check, backup, apply, restore, repeat, mode and inode')

    reset()
    with closing(sqlite3.connect(live)) as db, db:
        db.execute("UPDATE admin SET ival=132 WHERE key='version'")
    changed = contents(live)
    assert 'new-content-unverified' in run('apply', 1)
    assert 'new-content-unverified' in run('check')
    assert contents(live) == changed and not backup.exists()
    print('PASS unexpected content version refused')

    reset()
    with closing(sqlite3.connect(live)) as db, db:
        db.execute('BEGIN IMMEDIATE')
        assert 'locked' in run('apply', 1)
    assert contents(live) == baseline and not backup.exists()
    print('PASS busy database left intact')

    reset()
    backup.symlink_to(sample)
    assert 'private backup' in run('apply', 1)
    assert contents(live) == baseline
    print('PASS symlink backup refused')

    reset()
    keeper = sqlite3.connect(live)
    keeper.execute('PRAGMA journal_mode=WAL')
    keeper.execute('PRAGMA wal_autocheckpoint=0')
    keeper.execute("INSERT INTO admin VALUES('testWal', 42, NULL)")
    keeper.commit()
    wal_baseline = contents(live)
    wal_expected = wal_baseline[:2] + (expected[2],)
    run('apply')
    assert contents(live) == wal_expected and contents(backup) == wal_baseline
    run('restore')
    assert contents(live) == wal_baseline
    keeper.close()
    print('PASS WAL snapshot, transaction, and restore')

    # A newer content revision is accepted only against a prior local v131 baseline.
    reset()
    run('apply'); run('restore')
    with closing(sqlite3.connect(live)) as db, db:
        db.execute("UPDATE admin SET ival=132 WHERE key='version'")
    before = contents(live)
    assert 'new-content-identical' in run('check')
    assert 'explicit' in run('apply', 1)
    assert contents(live) == before
    run('apply-compatible:132:' + hashlib.sha256(bytes(1580)).hexdigest())
    assert len(contents(live)[2]) == len(before[2]) - 1
    newer_backup = Path(str(backup_base) + '.content-132')
    assert newer_backup.exists()
    run('restore')
    assert contents(live) == before
    print('PASS new version requires baseline and explicit confirmation; per-version restore')

    # Equal blob length does not imply the same policy.
    with closing(sqlite3.connect(live)) as db, db:
        db.execute("UPDATE rules SET policies=? WHERE policyName=? AND domainSuffix=? AND labelRegex=?", (bytes([1])*1580, *target))
    altered = contents(live)
    assert 'new-content-unverified' in run('apply-compatible:132:' + hashlib.sha256(bytes(1580)).hexdigest(), 1)
    assert contents(live) == altered
    print('PASS same-length changed policy refused')

    # A backup from another device/build scope cannot authorize writes or restoration.
    with closing(sqlite3.connect(backup)) as db, db:
        db.execute("UPDATE wloc_backup_metadata SET scope='other-device/os'")
    assert 'new-content-unverified' in run('apply-compatible:132:' + hashlib.sha256(bytes(1580)).hexdigest(), 1)
    assert contents(live) == altered
    print('PASS foreign baseline refused')

    with closing(sqlite3.connect(live)) as db, db:
        db.execute("DELETE FROM rules WHERE policyName=? AND domainSuffix=? AND labelRegex=?", target)
    without_rule = contents(live)
    with closing(sqlite3.connect(newer_backup)) as db, db:
        db.execute("UPDATE wloc_backup_metadata SET content=133")
    run('restore', 1)
    assert contents(live) == without_rule
    print('PASS mismatched restore metadata refused')

    reset()
    with closing(sqlite3.connect(live)) as db, db:
        db.execute("ALTER TABLE rules ADD COLUMN unexpected TEXT")
    assert 'Unsupported table structure' in run('check', 1)
    run('apply', 1)
    assert not backup.exists()
    print('PASS schema-number-preserving structure change refused')

    reset()
    with closing(sqlite3.connect(live)) as db, db:
        db.execute("CREATE TRIGGER changed AFTER DELETE ON rules BEGIN SELECT 1; END")
    run('apply', 1)
    assert not backup.exists()
    print('PASS triggers refused')
