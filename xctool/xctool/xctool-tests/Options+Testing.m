
#import "Options+Testing.h"

#import "FakeTask.h"
#import "FakeTaskManager.h"
#import "LaunchHandlers.h"
#import "XcodeSubjectInfo.h"
#import "XCToolUtil.h"

@implementation Options (Testing)

+ (Options *)optionsFrom:(NSArray *)arguments
{
  Options *options = [[[Options alloc] init] autorelease];

  NSString *errorMessage = nil;
  [options consumeArguments:[NSMutableArray arrayWithArray:arguments]
               errorMessage:&errorMessage];

  if (errorMessage != nil) {
    [NSException raise:NSGenericException
                format:@"Failed to parse options: %@", errorMessage];
  }

  return options;
}

- (Options *)assertReporterOptionsValidate
{
  NSString *errorMessage = nil;
  BOOL valid = [self validateReporterOptions:&errorMessage];

  if (!valid) {
    [NSException raise:NSGenericException
                format:@"Failed to validate reporter options: %@", errorMessage];
  }

  return self;
}

- (void)assertReporterOptionsFailToValidateWithError:(NSString *)message
{
  NSString *errorMessage = nil;
  BOOL valid = [self validateReporterOptions:&errorMessage];

  if (valid) {
    [NSException raise:NSGenericException
                format:@"Expected reporter validation to failed, but passed."];
  } else if (!valid && ![message isEqualToString:errorMessage]) {
    [NSException raise:NSGenericException
                format:
     @"Expected reporter validation to fail with message '%@' but "
     @"instead failed with '%@'", message, errorMessage];
  }
}


- (void)assertOptionsFailToValidateWithError:(NSString *)message
{
  NSString *errorMessage = nil;
  BOOL valid = [self validateOptions:&errorMessage
                    xcodeSubjectInfo:nil
                             options:self];

  if (valid) {
    [NSException raise:NSGenericException
                format:@"Expected validation to failed, but passed."];
  } else if (!valid && ![message isEqualToString:errorMessage]) {
    [NSException raise:NSGenericException
                format:
     @"Expected validation to fail with message '%@' but instead failed "
     @"with '%@'", message, errorMessage];
  }
}

- (void)evaluateOptionsWithBuildSettingsFromFile:(NSString *)path
                                           valid:(BOOL *)validOut
                                           error:(NSString **)errorOut
{
  NSString *contents = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
  if (contents == nil) {
    [NSException raise:NSGenericException
                format:@"Failed to read file from: %@", path];
  }

  XcodeSubjectInfo *subjectInfo = [[[XcodeSubjectInfo alloc] init] autorelease];

  __block NSString *error = nil;
  __block BOOL valid = NO;

  [[FakeTaskManager sharedManager] runBlockWithFakeTasks:^{
    [[FakeTaskManager sharedManager] addLaunchHandlerBlocks:@[
     [[^(FakeTask *task){
      if ([[task launchPath] hasSuffix:@"xcodebuild"] &&
          [[task arguments] containsObject:@"-showBuildSettings"]) {
        [task pretendTaskReturnsStandardOutput:contents];
      }
    } copy] autorelease],
     ]];

    valid = [self validateOptions:&error
                 xcodeSubjectInfo:subjectInfo
                          options:self];
    
  }];

  *validOut = valid;
  *errorOut = error;
}

- (void)assertOptionsFailToValidateWithError:(NSString *)message
                   withBuildSettingsFromFile:(NSString *)path
{
  NSString *errorMessage = nil;
  BOOL valid = NO;

  [self evaluateOptionsWithBuildSettingsFromFile:path
                                           valid:&valid
                                           error:&errorMessage];

  if (valid) {
    [NSException raise:NSGenericException
                format:@"Expected validation to failed, but passed."];
  } else if (!valid && ![message isEqualToString:errorMessage]) {
    [NSException raise:NSGenericException
                format:
     @"Expected validation to fail with message '%@' but instead "
     @"failed with '%@'", message, errorMessage];
  }
}

- (Options *)assertOptionsValidateWithBuildSettingsFromFile:(NSString *)path
{
  [self assertReporterOptionsValidate];
  
  NSString *errorMessage = nil;
  BOOL valid = NO;

  [self evaluateOptionsWithBuildSettingsFromFile:path
                                           valid:&valid
                                           error:&errorMessage];

  if (!valid) {
    [NSException raise:NSGenericException
                format:
     @"Expected validation to pass but failed with message '%@'", errorMessage];
  }

  return self;
}

@end
