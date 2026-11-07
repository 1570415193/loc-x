#import <UIKit/UIKit.h>
#include <stdio.h>
#include <errno.h>
#include <spawn.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "rules.h"

extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *, gid_t);

typedef struct __SecTask *HelperSecTaskRef;
extern HelperSecTaskRef SecTaskCreateFromSelf(CFAllocatorRef);
extern CFTypeRef SecTaskCopyValueForEntitlement(HelperSecTaskRef, CFStringRef, CFErrorRef *);

static void show_trustd_entitlements(void) {
    HelperSecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    CFTypeRef paths = task ? SecTaskCopyValueForEntitlement(task,
        CFSTR("com.apple.security.exception.files.absolute-path.read-write"), NULL) : NULL;
    int valid = paths && CFGetTypeID(paths) == CFArrayGetTypeID() &&
        CFArrayContainsValue((CFArrayRef)paths, CFRangeMake(0, CFArrayGetCount((CFArrayRef)paths)),
                             CFSTR("/private/var/protected/trustd/"));
    fprintf(stderr, "Installed trustd path entitlement: %s\n", valid ? "present" : "not reported");
    if (paths) CFRelease(paths);
    CFTypeRef storage = task ? SecTaskCopyValueForEntitlement(task,
        CFSTR("com.apple.private.security.storage.trustd"), NULL) : NULL;
    fprintf(stderr, "Installed trustd storage entitlement: %s\n",
            storage && CFEqual(storage, kCFBooleanTrue) ? "present" : "not reported");
    if (storage) CFRelease(storage);
    if (task) CFRelease(task);
}

NSString *RunRules(NSString *command, BOOL *success) {
    *success = NO;
    int output[2];
    if (pipe(output) != 0) return [NSString stringWithFormat:@"pipe: %s", strerror(errno)];
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_t actions;
    int error = posix_spawnattr_init(&attributes);
    BOOL haveAttributes = error == 0;
    if (!error) error = posix_spawnattr_set_persona_np(&attributes, 99, 1);
    if (!error) error = posix_spawnattr_set_persona_uid_np(&attributes, 0);
    if (!error) error = posix_spawnattr_set_persona_gid_np(&attributes, 0);
    BOOL haveActions = NO;
    if (!error) {
        error = posix_spawn_file_actions_init(&actions);
        haveActions = error == 0;
    }
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO);
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, output[1], STDERR_FILENO);
    if (!error) error = posix_spawn_file_actions_addclose(&actions, output[0]);
    if (!error) error = posix_spawn_file_actions_addclose(&actions, output[1]);
    NSString *path = NSBundle.mainBundle.executablePath;
    char *arguments[] = {(char *)path.fileSystemRepresentation, (char *)command.UTF8String, NULL};
    char *environment[] = {NULL};
    pid_t child = 0;
    if (!error) error = posix_spawn(&child, arguments[0], &actions, &attributes, arguments, environment);
    if (haveActions) posix_spawn_file_actions_destroy(&actions);
    if (haveAttributes) posix_spawnattr_destroy(&attributes);
    close(output[1]);
    if (error) {
        close(output[0]);
        return [NSString stringWithFormat:@"无法启动 root helper（%d）\n%s", error, strerror(error)];
    }
    const NSUInteger logLimit = 16 * 1024;
    NSMutableData *data = [NSMutableData data];
    BOOL truncated = NO;
    char buffer[1024];
    ssize_t length;
    do {
        length = read(output[0], buffer, sizeof(buffer));
        if (length > 0) {
            NSUInteger available = MIN((NSUInteger)length, logLimit - data.length);
            [data appendBytes:buffer length:available];
            truncated |= available < (NSUInteger)length;
        }
    } while (length > 0 || (length == -1 && errno == EINTR));
    int readError = length < 0 ? errno : 0;
    close(output[0]);
    int status = 0;
    pid_t waited;
    do { waited = waitpid(child, &status, 0); } while (waited == -1 && errno == EINTR);
    int waitError = waited == -1 ? errno : 0;
    *success = !readError && waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0;
    NSString *log = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!log && truncated) {
        // The byte limit may split a UTF-8 character at the end of the log.
        for (NSUInteger removed = 1; removed <= 3 && !log; removed++) {
            log = [[NSString alloc] initWithBytes:data.bytes length:data.length - removed
                                         encoding:NSUTF8StringEncoding];
        }
    }
    if (!log) log = @"Helper output is not valid UTF-8.";
    if (truncated) log = [log stringByAppendingString:@"\nHelper output truncated."];
    if (readError) log = [log stringByAppendingFormat:@"\nRead helper output: %s", strerror(readError)];
    if (waitError) {
        log = [log stringByAppendingFormat:@"\nWait for helper: %s", strerror(waitError)];
    } else if (WIFSIGNALED(status)) {
        log = [log stringByAppendingFormat:@"\nHelper exited on signal %d", WTERMSIG(status)];
    }
    return log;
}
