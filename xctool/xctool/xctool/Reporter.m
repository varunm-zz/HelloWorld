//
// Copyright 2013 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "Reporter.h"

#import <sys/stat.h>

#import "Options.h"
#import "JSONStreamReporter.h"
#import "JSONCompilationDatabaseReporter.h"
#import "JUnitReporter.h"
#import "PhabricatorReporter.h"
#import "TextReporter.h"

NSString *ReporterMessageLevelToString(ReporterMessageLevel level) {
  switch (level) {
    case REPORTER_MESSAGE_DEBUG:
      return @"Debug";
    case REPORTER_MESSAGE_VERBOSE:
      return @"Verbose";
    case REPORTER_MESSAGE_INFO:
      return @"Info";
    case REPORTER_MESSAGE_WARNING:
      return @"Warning";
    case REPORTER_MESSAGE_ERROR:
      return @"Error";
  }
}

static void ReportStatusMessageBeginWithTimestamp(NSArray *reporters, double timestamp, ReporterMessageLevel level, NSString *message) {
  NSDictionary *event = @{@"event": kReporter_Events_BeginStatus,
                          kReporter_BeginStatus_MessageKey: message,
                          kReporter_BeginStatus_TimestampKey: @(timestamp),
                          kReporter_BeginStatus_LevelKey: ReporterMessageLevelToString(level),
                          };
  [reporters makeObjectsPerformSelector:@selector(handleEvent:)
                             withObject:event];
}

static void ReportStatusMessageEndWithTimestamp(NSArray *reporters, double timestamp, ReporterMessageLevel level, NSString *message) {
  NSDictionary *event = @{@"event": kReporter_Events_EndStatus,
                          kReporter_EndStatus_MessageKey: message,
                          kReporter_EndStatus_TimestampKey: @(timestamp),
                          kReporter_EndStatus_LevelKey: ReporterMessageLevelToString(level),
                          };
  [reporters makeObjectsPerformSelector:@selector(handleEvent:)
                             withObject:event];
}

void ReportStatusMessage(NSArray *reporters, ReporterMessageLevel level, NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
  va_end(args);

  // This is a one-shot status message that has no begin/end, so we send the
  // same timestamp for both.
  double now = [[NSDate date] timeIntervalSince1970];
  ReportStatusMessageBeginWithTimestamp(reporters, now, level, message);
  ReportStatusMessageEndWithTimestamp(reporters, now, level, message);
}

void ReportStatusMessageBegin(NSArray *reporters, ReporterMessageLevel level, NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
  va_end(args);

  ReportStatusMessageBeginWithTimestamp(reporters, [[NSDate date] timeIntervalSince1970], level, message);
}


void ReportStatusMessageEnd(NSArray *reporters, ReporterMessageLevel level, NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
  va_end(args);

  ReportStatusMessageEndWithTimestamp(reporters, [[NSDate date] timeIntervalSince1970], level, message);
}


@implementation Reporter

+ (Reporter *)reporterWithName:(NSString *)name outputPath:(NSString *)outputPath options:(Options *)options
{
  NSDictionary *reporters = @{@"json-stream": [JSONStreamReporter class],
                              @"json-compilation-database": [JSONCompilationDatabaseReporter class],
                              @"junit": [JUnitReporter class],
                              @"pretty": [PrettyTextReporter class],
                              @"plain": [PlainTextReporter class],
                              @"phabricator": [PhabricatorReporter class],
                              };

  Class reporterClass = reporters[name];

  Reporter *reporter = [[[reporterClass alloc] init] autorelease];
  reporter.outputPath = outputPath;
  reporter.options = options;
  return reporter;
}

- (id)init
{
  if (self = [super init]) {
  }
  return self;
}

- (void)dealloc
{
  [_outputHandle release];
  [_outputPath release];
  [_options release];
  [super dealloc];
}

- (BOOL)openWithStandardOutput:(NSFileHandle *)standardOutput error:(NSString **)error
{
  if ([self.outputPath isEqualToString:@"-"]) {
    _outputHandle = [standardOutput retain];
    return YES;
  } else {
    NSFileManager *fileManager = [NSFileManager defaultManager];
      
    NSString *basePath = [self.outputPath stringByDeletingLastPathComponent];

    if ([basePath length] > 0) {
      BOOL isDirectory;
      BOOL exists = [fileManager fileExistsAtPath:basePath isDirectory:&isDirectory];
      if (!exists) {
        if (![fileManager createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil]) {
          *error = [NSString stringWithFormat:@"Failed to create folder at '%@'.", basePath];
          return NO;
        }
      }
    }
    
    if (![fileManager createFileAtPath:self.outputPath contents:nil attributes:nil]) {
      *error = [NSString stringWithFormat:@"Failed to create file at '%@'.", self.outputPath];
      return NO;
    }

    _outputHandle = [[NSFileHandle fileHandleForWritingAtPath:self.outputPath] retain];

    return YES;
  }
}

- (void)handleEvent:(NSDictionary *)eventDict
{
  NSAssert(([eventDict count] > 0), @"Event was empty.");

  NSString *event = eventDict[@"event"];
  NSAssert(event != nil && [event length] > 0, @"Event name was empty for event: %@", eventDict);

  NSMutableString *selectorName = [NSMutableString string];

  int i = 0;
  for (NSString *part in [event componentsSeparatedByString:@"-"]) {
    if (i++ == 0) {
      [selectorName appendString:[part lowercaseString]];
    } else {
      [selectorName appendString:[[part lowercaseString] capitalizedString]];
    }
  }
  [selectorName appendString:@":"];

  SEL sel = sel_registerName([selectorName UTF8String]);
  [self performSelector:sel withObject:eventDict];
}

- (void)beginAction:(NSDictionary *)event {}
- (void)endAction:(NSDictionary *)event {}
- (void)beginBuildTarget:(NSDictionary *)event {}
- (void)endBuildTarget:(NSDictionary *)event {}
- (void)beginBuildCommand:(NSDictionary *)event {}
- (void)endBuildCommand:(NSDictionary *)event {}
- (void)beginXcodebuild:(NSDictionary *)event {}
- (void)endXcodebuild:(NSDictionary *)event {}
- (void)beginOcunit:(NSDictionary *)event {}
- (void)endOcunit:(NSDictionary *)event {}
- (void)beginTestSuite:(NSDictionary *)event {}
- (void)endTestSuite:(NSDictionary *)event {}
- (void)beginTest:(NSDictionary *)event {}
- (void)endTest:(NSDictionary *)event {}
- (void)testOutput:(NSDictionary *)event {}
- (void)beginStatus:(NSDictionary *)event {}
- (void)endStatus:(NSDictionary *)event {}

- (void)close
{
  // Be sure everything gets flushed.
  struct stat fdstat = {0};
  NSAssert(fstat([_outputHandle fileDescriptor], &fdstat) == 0, @"fstat() failed: %s", strerror(errno));

  // Don't call synchronizeFile for pipes - it's not supported.  All of the automated
  // tests pass around pipes, so it's important to have this check.
  if (!S_ISFIFO(fdstat.st_mode)) {
    [_outputHandle synchronizeFile];
  }
}

@end
