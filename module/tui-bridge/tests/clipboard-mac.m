// clang -fobjc-arc -framework AppKit tests/clipboard-mac.m -o build/test-clipboard
// build/test-clipboard /absolute/path/to/.dotfiles
// Temporarily changes the clipboard and restores all original item types.
#import <AppKit/AppKit.h>

static void check(BOOL condition, NSString *message) {
    if (!condition) {
        [NSException raise:@"TestFailure" format:@"%@", message];
    }
}

static NSData *run(NSString *tool, NSArray<NSString *> *args) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = args;
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    [env removeObjectForKey:@"SSH_CLIENT"];
    [env removeObjectForKey:@"SSH_TTY"];
    env[@"PATH"] = [NSString stringWithFormat:@"%@:%@", tool.stringByDeletingLastPathComponent, env[@"PATH"]];
    task.environment = env;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    NSError *error = nil;
    check([task launchAndReturnError:&error], error.description);
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    check(task.terminationStatus == 0, @"subprocess failed");
    return data;
}

static NSDictionary *request(NSString *bridge, NSString *method, NSDictionary *params) {
    NSDictionary *body = @{@"id": @1, @"module": @"clipboard", @"method": method, @"params": params};
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSData *data = run(bridge, @[@"-j", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]);
    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    check([response[@"ok"] boolValue], @"bridge request failed");
    return response[@"result"];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        check(argc == 2, @"expected repository root");
        NSString *root = @(argv[1]);
        NSString *bridge = [root stringByAppendingPathComponent:@"module/tui-bridge/build/tui-bridge"];
        NSString *paste = [root stringByAppendingPathComponent:@"bin/common/p"];
        // p resolves the test build before the installed helper.
        setenv("PATH", [[NSString stringWithFormat:@"%@:%@", bridge.stringByDeletingLastPathComponent,
                         NSProcessInfo.processInfo.environment[@"PATH"]] UTF8String], 1);
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        check(pb.types != nil, @"system pasteboard unavailable");
        NSMutableArray *saved = [NSMutableArray array];
        for (NSPasteboardItem *item in pb.pasteboardItems) {
            NSPasteboardItem *copy = [NSPasteboardItem new];
            for (NSString *type in item.types) {
                NSData *data = [item dataForType:type];
                check(data != nil, @"cannot back up clipboard item");
                [copy setData:data forType:type];
            }
            [saved addObject:copy];
        }
        @try {
            [pb clearContents];
            check([pb setString:@"中文\r\nsecond line\n" forType:NSPasteboardTypeString], @"cannot write clipboard");
            check([request(bridge, @"image", @{})[@"data"] isEqual:@""], @"text detected as image");
            NSDictionary *text = request(bridge, @"output", @{@"eol": @"lf"});
            check([text isEqual:@{@"text": @"中文\nsecond line\n"}], @"legacy text response changed");
            check([run(paste, @[]) isEqual:[@"中文\nsecond line\n" dataUsingEncoding:NSUTF8StringEncoding]], @"p text mismatch");

            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:2 bitsPerSample:8
                samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                bytesPerRow:0 bitsPerPixel:0];
            memset(bitmap.bitmapData, 255, bitmap.bytesPerRow * bitmap.pixelsHigh);
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSData *tiff = bitmap.TIFFRepresentation;
            for (NSString *type in @[NSPasteboardTypePNG, NSPasteboardTypeTIFF]) {
                [pb clearContents];
                check([pb setData:[type isEqual:NSPasteboardTypePNG] ? png : tiff forType:type], @"cannot write image");
                NSDictionary *image = request(bridge, @"image", @{});
                check([image[@"mime"] isEqual:@"image/png"], @"wrong image MIME");
                NSData *decoded = [[NSData alloc] initWithBase64EncodedString:image[@"data"] options:0];
                NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:decoded];
                check(rep.pixelsWide == 2 && rep.pixelsHigh == 2, @"invalid PNG conversion");
                check([run(paste, @[]) isEqual:decoded], @"p image mismatch");
                check([request(bridge, @"output", @{}) isEqual:@{@"text": @""}], @"image changed legacy text output");
                // Text consumers still receive text when both types are present.
                check([pb setString:@"caption" forType:NSPasteboardTypeString], @"cannot add text");
                check([request(bridge, @"output", @{@"selection": @"primary"}) isEqual:@{@"text": @"caption"}], @"mixed clipboard text mismatch");
            }
            puts("macOS PNG/TIFF, p export, Unicode text and legacy response compatibility OK");
        } @finally {
            [pb clearContents];
            check(saved.count == 0 || [pb writeObjects:saved], @"cannot restore clipboard");
        }
    }
}
