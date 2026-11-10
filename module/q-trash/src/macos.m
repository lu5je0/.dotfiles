#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

// The returned error is malloc-owned; Rust releases it with libc::free.
int qtrash_mac_trash(const char *path, char **message) {
  @autoreleasepool {
    NSURL *url = [NSURL fileURLWithFileSystemRepresentation:path
                                              isDirectory:NO relativeToURL:nil];
    NSError *error = nil;
    if (url && [[NSFileManager defaultManager] trashItemAtURL:url
                                           resultingItemURL:nil error:&error]) {
      return 0;
    }
    *message = strdup(error ? error.localizedDescription.UTF8String
                            : "cannot represent filesystem path");
    return -1;
  }
}
