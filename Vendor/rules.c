#include "rules.h"
#include <errno.h>
#include <fcntl.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>
#include <sys/sysctl.h>
#include <CommonCrypto/CommonDigest.h>

#ifndef WLOC_LIVE_DB
#define WLOC_LIVE_DB "/private/var/protected/trustd/pinningrules.sqlite3"
#endif
#ifndef WLOC_BACKUP_DB
#define WLOC_BACKUP_DB "/private/var/root/wloc-pinning-v131.sqlite3"
#endif

#define TARGET_POLICY "'AppleIssued'"
#define TARGET_SUFFIX "'apple.com'"
#define TARGET_LABELS "'^gs-loc$|^gs-loc-cn$'"
#define MATCH "policyName=" TARGET_POLICY " AND domainSuffix=" TARGET_SUFFIX \
              " AND labelRegex=" TARGET_LABELS

enum { TARGET_POLICY_BYTES = 1580 };
static int live_version;
static char backup_path[PATH_MAX];
static char device_scope[256];
static sqlite3_stmt *read_rule(sqlite3 *db);
static int compatibility(sqlite3 *db, int count);
static int metadata_matches(sqlite3 *db, int version);
static int set_backup_path(int version) {
    int n = snprintf(backup_path, sizeof(backup_path), "%s.content-%d", WLOC_BACKUP_DB, version);
    return n > 0 && (size_t)n < sizeof(backup_path);
}
static int load_device_scope(int create) {
#ifdef WLOC_TEST_SCOPE
    (void)create;
    snprintf(device_scope, sizeof(device_scope), "%s", WLOC_TEST_SCOPE);
    return 1;
#else
    // A root-private token is stable across reboots and cannot be inferred from the model.
    const char *path="/private/var/root/wloc-device-scope";
    int fd=open(path,O_RDONLY|O_NOFOLLOW); unsigned char token[32];
    if(fd<0 && errno==ENOENT && create) {
        arc4random_buf(token,sizeof(token));
        fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
        if(fd>=0){int ok=write(fd,token,sizeof(token))==sizeof(token) && fsync(fd)==0;close(fd);if(!ok)return 0;}
        fd=open(path,O_RDONLY|O_NOFOLLOW);
    }
    if(fd<0)return 0;
    struct stat st; int ok=fstat(fd,&st)==0 && S_ISREG(st.st_mode) &&
        st.st_uid==geteuid() && (st.st_mode&0777)==0600 && st.st_size==sizeof(token) &&
        read(fd,token,sizeof(token))==sizeof(token);
    close(fd);if(!ok)return 0;
    char machine[64],build[64];size_t m=sizeof(machine),b=sizeof(build);
    if(sysctlbyname("hw.machine",machine,&m,NULL,0)||sysctlbyname("kern.osversion",build,&b,NULL,0))return 0;
    char hex[65];for(int i=0;i<32;i++)snprintf(hex+i*2,3,"%02x",token[i]);
    snprintf(device_scope,sizeof(device_scope),"%s/%s/%s",machine,build,hex);return 1;
#endif
}
static void fingerprint(sqlite3_stmt *row, char hex[65]) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(sqlite3_column_blob(row,0),(CC_LONG)sqlite3_column_bytes(row,0),digest);
    for(int i=0;i<32;i++) snprintf(hex+i*2,3,"%02x",digest[i]);
}


static void sqlite_error(sqlite3 *db, const char *operation, const char *message) {
    fprintf(stderr, "%s: %s (SQLite %d, errno %d)\n", operation,
            message ? message : sqlite3_errmsg(db), sqlite3_extended_errcode(db), sqlite3_system_errno(db));
}

static int execute(sqlite3 *db, const char *sql) {
    char *error = NULL;
    int result = sqlite3_exec(db, sql, NULL, NULL, &error);
    if (result != SQLITE_OK) {
        const char *operation = strncmp(sql, "DELETE", 6) == 0 ? "Delete target rule" : sql;
        sqlite_error(db, operation, error);
    }
    sqlite3_free(error);
    return result == SQLITE_OK;
}

static void show_file(const char *label, const char *path) {
    struct stat attrs;
    if (lstat(path, &attrs) != 0) {
        int error = errno;
        printf("%s: %s (%d)\n", label, strerror(error), error);
        return;
    }
    printf("%s: uid=%u gid=%u mode=%04o", label, (unsigned)attrs.st_uid,
           (unsigned)attrs.st_gid, (unsigned)(attrs.st_mode & 07777));
#ifdef __APPLE__
    printf(" flags=0x%x", (unsigned)attrs.st_flags);
#endif
    puts("");
}

static int show_live_access(void) {
    char directory[] = WLOC_LIVE_DB;
    *strrchr(directory, '/') = '\0';
    show_file("trustd directory", directory);
    show_file("Live DB", WLOC_LIVE_DB);
    show_file("WAL", WLOC_LIVE_DB "-wal");
    show_file("SHM", WLOC_LIVE_DB "-shm");
    show_file("Journal", WLOC_LIVE_DB "-journal");
    int fd = open(WLOC_LIVE_DB, O_RDWR | O_NOFOLLOW);
    if (fd == -1) {
        int error = errno;
        printf("Live DB open(O_RDWR): %s (%d)\n", strerror(error), error);
    } else {
        close(fd);
        puts("Live DB open(O_RDWR): OK");
    }
    if (access(directory, W_OK | X_OK) != 0) {
        int error = errno;
        printf("Directory access(W_OK|X_OK): %s (%d)\n", strerror(error), error);
    } else {
        puts("Directory access(W_OK|X_OK): OK (file creation not tested)");
    }
    return fd != -1;
}

static void show_journal_mode(sqlite3 *db) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, "PRAGMA journal_mode", -1, &statement, NULL) == SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_text(statement, 0)) {
        printf("Live journal mode: %s\n", (const char *)sqlite3_column_text(statement, 0));
    } else {
        sqlite_error(db, "Read journal mode", NULL);
    }
    sqlite3_finalize(statement);
}

static int scalar(sqlite3 *db, const char *sql, int *value) {
    sqlite3_stmt *stmt = NULL;
    int ok = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK &&
             sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) == SQLITE_INTEGER;
    if (ok) *value = sqlite3_column_int(stmt, 0);
    if (!ok) fprintf(stderr, "Database metadata: %s\n", sqlite3_errmsg(db));
    sqlite3_finalize(stmt);
    return ok;
}

static int inspect(sqlite3 *db, int *count) {
    int version = -1, schema = -1, triggers = -1;
    if (!scalar(db, "SELECT ival FROM admin WHERE key='version'", &version) ||
        !scalar(db, "PRAGMA user_version", &schema) ||
        !scalar(db, "SELECT count(*) FROM sqlite_master WHERE type='trigger'", &triggers)) return 0;
    printf("%s content: %d; schema: %d\n",
           strcmp(sqlite3_db_filename(db, "main"), WLOC_LIVE_DB) != 0 ? "Backup DB" : "Live DB",
           version, schema);
    if (version < 131 || schema != 3 || triggers != 0) {
        fprintf(stderr, "Expected content >= 131, schema 3 and no triggers.\n");
        return 0;
    }
    const char *tables[] = {"admin", "rules"};
    const char *names[][5] = {{"key","ival","value",NULL,NULL},
        {"policyName","domainSuffix","labelRegex","policies","transparentConnection"}};
    const char *types[][5] = {{"TEXT","INTEGER","BLOB",NULL,NULL},
        {"TEXT","TEXT","TEXT","BLOB","INTEGER"}};
    for(int t=0;t<2;t++) {
        char sql[80]; snprintf(sql,sizeof(sql),"PRAGMA table_info(%s)",tables[t]);
        sqlite3_stmt *columns=NULL; int expected=t?5:3, seen=0;
        if(sqlite3_prepare_v2(db,sql,-1,&columns,NULL)!=SQLITE_OK)return 0;
        while(sqlite3_step(columns)==SQLITE_ROW) {
            const char *name=(const char *)sqlite3_column_text(columns,1);
            const char *type=(const char *)sqlite3_column_text(columns,2);
            if(seen>=expected || !name || !type || strcmp(name,names[t][seen]) ||
                sqlite3_stricmp(type,types[t][seen])) { seen=-1; break; }
            seen++;
        }
        sqlite3_finalize(columns);
        if(seen!=expected){fprintf(stderr,"Unsupported table structure: %s.\n",tables[t]);return 0;}
        sqlite3_stmt *kind=NULL;
        int valid=sqlite3_prepare_v2(db,"SELECT type FROM sqlite_master WHERE name=?",-1,&kind,NULL)==SQLITE_OK &&
            sqlite3_bind_text(kind,1,tables[t],-1,SQLITE_STATIC)==SQLITE_OK && sqlite3_step(kind)==SQLITE_ROW &&
            strcmp((const char *)sqlite3_column_text(kind,0),"table")==0;
        sqlite3_finalize(kind); if(!valid)return 0;
    }
    sqlite3_stmt *check = NULL;
    int ok = sqlite3_prepare_v2(db, "PRAGMA quick_check(1)", -1, &check, NULL) == SQLITE_OK &&
             sqlite3_step(check) == SQLITE_ROW && sqlite3_column_text(check, 0) &&
             strcmp((const char *)sqlite3_column_text(check, 0), "ok") == 0;
    sqlite3_finalize(check);
    if (!ok) {
        fprintf(stderr, "Database integrity check failed.\n");
        return 0;
    }
    if (!scalar(db, "SELECT count(*) FROM rules WHERE " MATCH, count)) return 0;
    if (*count > 1) {
        fprintf(stderr, "Expected at most one target rule; found %d.\n", *count);
        return 0;
    }
    return 1;
}

static sqlite3 *open_db(const char *path, int flags) {
    struct stat attrs;
    if (lstat(path, &attrs) != 0) {
        fprintf(stderr, "Cannot access %s: %s\n", path, strerror(errno));
        return NULL;
    }
    if (!S_ISREG(attrs.st_mode)) {
        fprintf(stderr, "Expected a regular database file: %s\n", path);
        return NULL;
    }
#ifdef SQLITE_OPEN_NOFOLLOW
    flags |= SQLITE_OPEN_NOFOLLOW;
#endif
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path, &db, flags, NULL) != SQLITE_OK) {
        sqlite_error(db, path, NULL);
        sqlite3_close(db);
        return NULL;
    }
    sqlite3_busy_timeout(db, 2000);
    if (!execute(db, "PRAGMA trusted_schema=OFF")) {
        sqlite3_close(db);
        return NULL;
    }
    return db;
}

static sqlite3_stmt *read_rule(sqlite3 *db) {
    sqlite3_stmt *row = NULL;
    if (sqlite3_prepare_v2(db, "SELECT policies,transparentConnection FROM rules WHERE " MATCH,
                           -1, &row, NULL) == SQLITE_OK && sqlite3_step(row) == SQLITE_ROW &&
        sqlite3_column_type(row, 0) == SQLITE_BLOB &&
        sqlite3_column_bytes(row, 0) == TARGET_POLICY_BYTES &&
        sqlite3_column_type(row, 1) == SQLITE_INTEGER && sqlite3_column_int(row, 1) == 0) return row;
    fprintf(stderr, "The target rule differs from the expected v131 rule.\n");
    sqlite3_finalize(row);
    return NULL;
}

static int create_backup(void) {
    char path[PATH_MAX];
    if(snprintf(path,sizeof(path),"%s.tmp.XXXXXX",backup_path)>=(int)sizeof(path))return 0;
    int fd = mkstemp(path);
    if (fd < 0) {
        fprintf(stderr, "Cannot create backup: %s\n", strerror(errno));
        return 0;
    }
    sqlite3 *src = open_db(WLOC_LIVE_DB, SQLITE_OPEN_READONLY);
    sqlite3 *dst = src ? open_db(path, SQLITE_OPEN_READWRITE) : NULL;
    sqlite3_backup *backup = dst ? sqlite3_backup_init(dst, "main", src, "main") : NULL;
    int ok = 0;
    if (backup) {
        int step = sqlite3_backup_step(backup, -1);
        int finish = sqlite3_backup_finish(backup);
        ok = step == SQLITE_DONE && finish == SQLITE_OK;
    }
    if (ok) ok = execute(dst, "PRAGMA journal_mode=DELETE");
    if (ok) {
        sqlite3_stmt *row=read_rule(dst); char hash[65];
        if(!row) ok=0;
        else {fingerprint(row,hash);sqlite3_finalize(row);
            ok=execute(dst,"CREATE TABLE wloc_backup_metadata(format INTEGER,content INTEGER,scope TEXT,fingerprint TEXT)");
            sqlite3_stmt *meta=NULL;
            ok=ok && sqlite3_prepare_v2(dst,"INSERT INTO wloc_backup_metadata VALUES(1,?,?,?)",-1,&meta,NULL)==SQLITE_OK &&
                sqlite3_bind_int(meta,1,live_version)==SQLITE_OK &&
                sqlite3_bind_text(meta,2,device_scope,-1,SQLITE_TRANSIENT)==SQLITE_OK &&
                sqlite3_bind_text(meta,3,hash,-1,SQLITE_TRANSIENT)==SQLITE_OK && sqlite3_step(meta)==SQLITE_DONE;
            sqlite3_finalize(meta);
        }
    }
    if (!ok && dst) fprintf(stderr, "SQLite backup: %s\n", sqlite3_errmsg(dst));
    if (dst) sqlite3_close(dst);
    if (src) sqlite3_close(src);
    if (ok && (fsync(fd) != 0 || link(path, backup_path) != 0)) {
        fprintf(stderr, "Cannot save backup: %s\n", strerror(errno));
        ok = 0;
    }
    close(fd);
    unlink(path);
    return ok;
}

static sqlite3 *checked_backup(void) {
    struct stat attrs;
    if (lstat(backup_path, &attrs) != 0 || !S_ISREG(attrs.st_mode) ||
        attrs.st_uid != geteuid() || (attrs.st_mode & 0777) != 0600) {
        fprintf(stderr, "A private backup owned by the helper is required.\n");
        return NULL;
    }
    sqlite3 *backup = open_db(backup_path, SQLITE_OPEN_READONLY);
    int count = 0;
    if (backup && (!inspect(backup, &count) || count != 1 || !metadata_matches(backup, live_version))) {
        sqlite3_close(backup);
        return NULL;
    }
    return backup;
}

static int metadata_matches(sqlite3 *db, int version) {
    int actual=-1; if(!scalar(db,"SELECT ival FROM admin WHERE key='version'",&actual) || actual!=version)return 0;
    sqlite3_stmt *row=read_rule(db);char hash[65];if(!row)return 0;fingerprint(row,hash);sqlite3_finalize(row);
    sqlite3_stmt *meta=NULL;
    int ok=sqlite3_prepare_v2(db,"SELECT format,content,scope,fingerprint FROM wloc_backup_metadata",-1,&meta,NULL)==SQLITE_OK &&
        sqlite3_step(meta)==SQLITE_ROW && sqlite3_column_int(meta,0)==1 && sqlite3_column_int(meta,1)==version &&
        sqlite3_column_type(meta,2)==SQLITE_TEXT && sqlite3_column_type(meta,3)==SQLITE_TEXT &&
        strcmp((const char *)sqlite3_column_text(meta,2),device_scope)==0 &&
        strcmp((const char *)sqlite3_column_text(meta,3),hash)==0 && sqlite3_step(meta)==SQLITE_DONE;
    sqlite3_finalize(meta);if(!ok)fprintf(stderr,"Backup metadata/fingerprint/device scope mismatch.\n");return ok;
}
static int compatibility(sqlite3 *db, int count) {
    if(!count){puts("Compatibility: target-absent");return 0;}
    sqlite3_stmt *current=read_rule(db);if(!current){puts("Compatibility: policy-format-unknown");return 0;}
    char hash[65];fingerprint(current,hash);printf("Policy SHA256: %s\n",hash);
    if(live_version==131){sqlite3_finalize(current);puts("Compatibility: v131-local-baseline (upstream format checks, not an official digest allowlist)");return 1;}
    char saved_path[PATH_MAX];strcpy(saved_path,backup_path);set_backup_path(131);
    int saved_version=live_version;live_version=131;sqlite3 *baseline=checked_backup();live_version=saved_version;strcpy(backup_path,saved_path);
    sqlite3_stmt *saved=baseline?read_rule(baseline):NULL;
    int same=saved && memcmp(sqlite3_column_blob(current,0),sqlite3_column_blob(saved,0),TARGET_POLICY_BYTES)==0;
    sqlite3_finalize(current);sqlite3_finalize(saved);if(baseline)sqlite3_close(baseline);
    puts(same?"Compatibility: new-content-identical":"Compatibility: new-content-unverified");return same;
}

static int apply(sqlite3 *db) {
    sqlite3_stmt *current = read_rule(db);
    if (!current) return 0;
    struct stat attrs;
    int found = lstat(backup_path, &attrs);
    if (found != 0 && errno == ENOENT && !create_backup()) {
        sqlite3_finalize(current);
        return 0;
    }
    sqlite3 *backup = checked_backup();
    sqlite3_stmt *saved = backup ? read_rule(backup) : NULL;
    int equal = saved && memcmp(sqlite3_column_blob(current, 0), sqlite3_column_blob(saved, 0),
                               TARGET_POLICY_BYTES) == 0;
    sqlite3_finalize(current);
    sqlite3_finalize(saved);
    if (backup) sqlite3_close(backup);
    if (!equal) {
        fprintf(stderr, "The existing backup does not match the target rule.\n");
        return 0;
    }
    return execute(db, "DELETE FROM rules WHERE " MATCH) && sqlite3_changes(db) == 1;
}

static int restore(sqlite3 *db) {
    sqlite3 *backup = checked_backup();
    if (!backup) return 0;
    sqlite3_stmt *row = read_rule(backup);
    sqlite3_stmt *insert = NULL;
    int ok = row && sqlite3_prepare_v2(db,
        "INSERT INTO rules(policyName,domainSuffix,labelRegex,policies,transparentConnection) "
        "VALUES(" TARGET_POLICY "," TARGET_SUFFIX "," TARGET_LABELS ",?,0)", -1, &insert, NULL) == SQLITE_OK &&
        sqlite3_bind_blob(insert, 1, sqlite3_column_blob(row, 0), TARGET_POLICY_BYTES,
                          SQLITE_TRANSIENT) == SQLITE_OK &&
        sqlite3_step(insert) == SQLITE_DONE && sqlite3_changes(db) == 1;
    if (!ok) sqlite_error(db, "Restore target rule", NULL);
    sqlite3_finalize(insert);
    sqlite3_finalize(row);
    sqlite3_close(backup);
    return ok;
}

int run_rules_command(const char *command) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int check = strcmp(command, "check") == 0;
    int expected_version=0;char expected_hash[65]={0},trailing=0;
    int acknowledged=strncmp(command,"apply-compatible:",17)==0;
    if(acknowledged && (sscanf(command+17,"%d:%64[0-9a-f]%c",&expected_version,expected_hash,&trailing)!=2 || strlen(expected_hash)!=64))return 64;
    int applying = strcmp(command, "apply") == 0 || acknowledged;
    if (!check && !applying && strcmp(command, "restore") != 0) return 64;
    printf("Helper effective UID: %u; real UID: %u; effective GID: %u\n",
           (unsigned)geteuid(), (unsigned)getuid(), (unsigned)getegid());
    if (geteuid() != 0) {
        fprintf(stderr, "The helper must run as root.\n");
        return 1;
    }
    int live_writable = show_live_access();
    if (!check && !live_writable) {
        fprintf(stderr, "The OS refused a writable file descriptor. No write transaction was started.\n");
        return 1;
    }
    sqlite3 *db = open_db(WLOC_LIVE_DB, check ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE);
    if (!db) return 1;
    if(!scalar(db,"SELECT ival FROM admin WHERE key='version'",&live_version) || !set_backup_path(live_version)){sqlite3_close(db);return 1;}
    if(!load_device_scope(applying && live_version==131)){
        device_scope[0]=0;puts("Device scope: unavailable (no compatible backup can be trusted)");
        if(!check){fprintf(stderr,"Cannot establish private device scope; write refused.\n");sqlite3_close(db);return 1;}
    }
    show_journal_mode(db);
    if (!check) printf("SQLite write connection readonly: %d\n", sqlite3_db_readonly(db, "main"));
    int count = 0;
    int ok = (check || execute(db, "BEGIN IMMEDIATE")) && inspect(db, &count);
    if (ok && check) {
        printf("Target rule: %s\n", count ? "present" : "absent");
        compatibility(db,count);
    } else if (ok && count == applying) {
        if(applying) {
            ok=compatibility(db,count);
            if(ok && acknowledged){
                sqlite3_stmt *row=read_rule(db);char actual[65]={0};if(row){fingerprint(row,actual);sqlite3_finalize(row);}
                if(expected_version!=live_version || strcmp(expected_hash,actual)){fprintf(stderr,"Confirmed version/fingerprint changed; check again.\n");ok=0;}
            }
            if(ok && live_version>131 && !acknowledged){fprintf(stderr,"New content requires explicit compatible-version confirmation.\n");ok=0;}
        }
        if(ok) ok = applying ? apply(db) : restore(db);
        int after = -1;
        ok = ok && scalar(db, "SELECT count(*) FROM rules WHERE " MATCH, &after) && after == !applying;
        ok = ok && execute(db, "COMMIT");
        if (ok) printf("%s. Restart iPhone to validate with trustd.\n", applying ? "Applied" : "Restored");
    } else if (ok) {
        printf("Target rule is already %s.\n", applying ? "absent" : "present");
    }
    if (!sqlite3_get_autocommit(db)) execute(db, "ROLLBACK");
    sqlite3_close(db);
    return ok ? 0 : 1;
}
