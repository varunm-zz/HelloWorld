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

#import "RunTestsAction.h"

#import "BufferedReporter.h"
#import "OCUnitIOSAppTestRunner.h"
#import "OCUnitIOSLogicTestRunner.h"
#import "OCUnitOSXAppTestRunner.h"
#import "OCUnitOSXLogicTestRunner.h"
#import "Options.h"
#import "Reporter.h"
#import "TaskUtil.h"
#import "XcodeSubjectInfo.h"
#import "XCToolUtil.h"

@implementation RunTestsAction {
  NSLock *_appTestLock;
}

+ (NSString *)name
{
  return @"run-tests";
}

+ (NSArray *)options
{
  return
  @[
    [Action actionOptionWithName:@"test-sdk"
                         aliases:nil
                     description:@"SDK to test with"
                       paramName:@"SDK"
                           mapTo:@selector(setTestSDK:)],
    [Action actionOptionWithName:@"only"
                         aliases:nil
                     description:@"SPEC is TARGET[:Class/case[,Class2/case2]]"
                       paramName:@"SPEC"
                           mapTo:@selector(addOnly:)],
    [Action actionOptionWithName:@"freshSimulator"
                         aliases:nil
                     description:
     @"Start fresh simulator for each application test target"
                         setFlag:@selector(setFreshSimulator:)],
    [Action actionOptionWithName:@"freshInstall"
                         aliases:nil
                     description:
     @"Use clean install of TEST_HOST for every app test run"
                         setFlag:@selector(setFreshInstall:)],
    [Action actionOptionWithName:@"parallelize"
                         aliases:nil
                     description:@"Parallelize execution of logic tests"
                         setFlag:@selector(setParallelize:)],
    ];
}

- (id)init
{
  if (self = [super init]) {
    self.onlyList = [NSMutableArray array];
    self->_appTestLock = [[NSLock alloc] init];
  }
  return self;
}

- (void)dealloc {
  self.onlyList = nil;
  self.testSDK = nil;
  [self->_appTestLock release];
  [super dealloc];
}

- (void)addOnly:(NSString *)argument
{
  [self.onlyList addObject:argument];
}


- (NSArray *)onlyListAsTargetsAndSenTestList
{
  NSMutableArray *results = [NSMutableArray array];

  for (NSString *only in self.onlyList) {
    NSRange colonRange = [only rangeOfString:@":"];
    NSString *target = nil;
    NSString *senTestList = nil;

    if (colonRange.length > 0) {
      target = [only substringToIndex:colonRange.location];
      senTestList = [only substringFromIndex:colonRange.location + 1];
    } else {
      target = only;
    }

    [results addObject:@{
     @"target": target,
     @"senTestList": senTestList ? senTestList : [NSNull null]
     }];
  }

  return results;
}

- (BOOL)validateOptions:(NSString **)errorMessage
          xcodeSubjectInfo:(XcodeSubjectInfo *)xcodeSubjectInfo
         options:(Options *)options
{
  if (self.testSDK == nil) {
    // If specified test SDKs aren't provided, just inherit the main SDK.
    self.testSDK = options.sdk;
  }

  if (![self validateSDK:self.testSDK]) {
    *errorMessage = [NSString stringWithFormat:@"run-tests: '%@' is not a supported SDK for testing.", self.testSDK];
    return NO;
  }

  for (NSDictionary *only in [self onlyListAsTargetsAndSenTestList]) {
    if ([xcodeSubjectInfo testableWithTarget:only[@"target"]] == nil) {
      *errorMessage = [NSString stringWithFormat:@"run-tests: '%@' is not a testing target in this scheme.", only[@"target"]];
      return NO;
    }
  }

  return YES;
}

- (BOOL)performActionWithOptions:(Options *)options xcodeSubjectInfo:(XcodeSubjectInfo *)xcodeSubjectInfo
{
  NSArray *testables = nil;

  if (self.onlyList.count == 0) {
    // Use whatever we found in the scheme, except for skipped tests.
    NSMutableArray *unskipped = [NSMutableArray array];
    for (NSDictionary *testable in xcodeSubjectInfo.testables) {
      if (![testable[@"skipped"] boolValue]) {
        [unskipped addObject:testable];
      }
    }
    testables = unskipped;
  } else {
    // Munge the list of testables from the scheme to only include those given.
    NSMutableArray *newTestables = [NSMutableArray array];
    for (NSDictionary *only in [self onlyListAsTargetsAndSenTestList]) {
      NSDictionary *matchingTestable = [xcodeSubjectInfo testableWithTarget:only[@"target"]];

      if (matchingTestable) {
        NSMutableDictionary *newTestable = [NSMutableDictionary dictionaryWithDictionary:matchingTestable];

        if (only[@"senTestList"] != [NSNull null]) {
          newTestable[@"senTestList"] = only[@"senTestList"];
          newTestable[@"senTestInvertScope"] = @NO;
        }

        [newTestables addObject:newTestable];
      }
    }
    testables = newTestables;
  }

  if (![self runTestables:testables
                  testSDK:self.testSDK
           freshSimulator:[self freshSimulator]
             freshInstall:[self freshInstall]
                  options:options
         xcodeSubjectInfo:xcodeSubjectInfo]) {
    return NO;
  }

  return YES;
}

+ (NSString *)stringWithMacrosExpanded:(NSString *)str
                     fromBuildSettings:(NSDictionary *)settings
{
  NSMutableString *result = [NSMutableString stringWithString:str];

  [settings enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *val, BOOL *stop){
    NSString *macroStr = [[NSString alloc] initWithFormat:@"$(%@)", key];
    [result replaceOccurrencesOfString:macroStr
                            withString:val
                               options:0
                                 range:NSMakeRange(0, [result length])];
    [macroStr release];
  }];

  return result;
}

- (NSArray *)argumentsWithMacrosExpanded:(NSArray *)arr
                       fromBuildSettings:(NSDictionary *)settings
{
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:[arr count]];

  for (NSString *str in arr) {
    [result addObject:[[self class] stringWithMacrosExpanded:str
                                           fromBuildSettings:settings]];
  }

  return result;
}

- (NSDictionary *)enviornmentWithMacrosExpanded:(NSDictionary *)dict
                              fromBuildSettings:(NSDictionary *)settings
{
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[dict count]];

  for (NSString *key in [dict allKeys]) {
    NSString *keyExpanded = [[self class] stringWithMacrosExpanded:key
                                                 fromBuildSettings:settings];
    NSString *valExpanded = [[self class] stringWithMacrosExpanded:dict[key]
                                                 fromBuildSettings:settings];
    result[keyExpanded] = valExpanded;
  }

  return result;
}

static NSString* const kTestableBlock = @"block";
static NSString* const kTestableMustRunInMainThread = @"mustRunInMainThread";

/*!
 Retrieves build params of the test and prepares a block that will run the test.

 @return  an NSDicitonary of the block that runs the test, and whether the test
          must be run on the main thread
 */
- (NSDictionary *) blockForTestable:(NSDictionary *)testable
                          reporters:(NSArray *)reporters
                            objRoot:(NSString *)objRoot
                            symRoot:(NSString *)symRoot
                  sharedPrecompsDir:(NSString *)sharedPrecompsDir
                     xcodeArguments:(NSArray *)xcodeArguments
                            testSDK:(NSString *)testSDK
                     freshSimulator:(BOOL)freshSimulator
                       freshInstall:(BOOL)freshInstall
                        senTestList:(NSString *)senTestList
                 senTestInvertScope:(BOOL)senTestInvertScope
{
  NSString *testableProjectPath = testable[@"projectPath"];
  NSString *testableTarget = testable[@"target"];

  // Collect build settings for this test target.
  NSTask *settingsTask = [[[NSTask alloc] init] autorelease];
  [settingsTask setLaunchPath:[XcodeDeveloperDirPath() stringByAppendingPathComponent:@"usr/bin/xcodebuild"]];
  [settingsTask setArguments:[xcodeArguments arrayByAddingObjectsFromArray:@[
                              @"-sdk", testSDK,
                              @"-project", testableProjectPath,
                              @"-target", testableTarget,
                              [NSString stringWithFormat:@"OBJROOT=%@", objRoot],
                              [NSString stringWithFormat:@"SYMROOT=%@", symRoot],
                              [NSString stringWithFormat:@"SHARED_PRECOMPS_DIR=%@", sharedPrecompsDir],
                              @"-showBuildSettings",
                              ]]];
  [settingsTask setEnvironment:@{
   @"DYLD_INSERT_LIBRARIES" : [PathToXCToolBinaries() stringByAppendingPathComponent:@"xcodebuild-fastsettings-shim.dylib"],
   @"SHOW_ONLY_BUILD_SETTINGS_FOR_TARGET" : testableTarget,
   }];

  NSDictionary *result = LaunchTaskAndCaptureOutput(settingsTask);
  NSDictionary *allSettings = BuildSettingsFromOutput(result[@"stdout"]);
  assert(allSettings.count == 1);
  NSDictionary *testableBuildSettings = allSettings[testableTarget];

  NSArray *arguments = testable[@"arguments"];
  NSDictionary *environment = testable[@"environment"];

  // In Xcode, you can optionally include variables in your args or environment
  // variables.  i.e. "$(ARCHS)" gets transformed into "armv7".
  if ([testable[@"macroExpansionProjectPath"] isNotEqualTo:[NSNull null]]) {
    arguments = [self argumentsWithMacrosExpanded:arguments
                                fromBuildSettings:testableBuildSettings];
    environment = [self enviornmentWithMacrosExpanded:environment
                                    fromBuildSettings:testableBuildSettings];
  }

  NSString *sdkName = testableBuildSettings[@"SDK_NAME"];
  BOOL isApplicationTest = testableBuildSettings[@"TEST_HOST"] != nil;

  // array of [class, (bool) GC Enabled]
  NSMutableArray *testConfigurations = [NSMutableArray array];

  if ([sdkName hasPrefix:@"iphonesimulator"]) {
    if (isApplicationTest) {
      [testConfigurations addObject:@[[OCUnitIOSAppTestRunner class], @NO]];
    } else {
      [testConfigurations addObject:@[[OCUnitIOSLogicTestRunner class], @NO]];
    }
  } else if ([sdkName hasPrefix:@"macosx"]) {
    Class testClass = {0};
    if (isApplicationTest) {
      testClass = [OCUnitOSXAppTestRunner class];
    } else {
      testClass = [OCUnitOSXLogicTestRunner class];
    }

    NSString *enableGC = testableBuildSettings[@"GCC_ENABLE_OBJC_GC"];

    if ([enableGC isEqualToString:@"required"]) {
      [testConfigurations addObject:@[testClass, @YES]];
    } else if ([enableGC isEqualToString:@"supported"]) {
      // If GC is marked as 'supported', Apple's normal unit-testing harness will run tests twice,
      // once with GC off and once with GC on.
      [testConfigurations addObject:@[testClass, @YES]];
      [testConfigurations addObject:@[testClass, @NO]];
    } else {
      [testConfigurations addObject:@[testClass, @NO]];
    }
  } else {
    NSAssert(NO, @"Unexpected SDK: %@", sdkName);
  }

  BOOL (^action)() = ^() {
    BOOL succeeded = YES;

    for (NSArray *testConfiguration in testConfigurations) {
      Class testRunnerClass = testConfiguration[0];
      BOOL garbageCollectionEnabled = [testConfiguration[1] boolValue];

      OCUnitTestRunner *testRunner = [[[testRunnerClass alloc]
                                       initWithBuildSettings:testableBuildSettings
                                       senTestList:senTestList
                                       senTestInvertScope:senTestInvertScope
                                       arguments:arguments
                                       environment:environment
                                       garbageCollection:garbageCollectionEnabled
                                       freshSimulator:freshSimulator
                                       freshInstall:freshInstall
                                       standardOutput:nil
                                       standardError:nil
                                       reporters:reporters] autorelease];

      NSDictionary *commonEventInfo = @{kReporter_BeginOCUnit_BundleNameKey: testableBuildSettings[@"FULL_PRODUCT_NAME"],
                                        kReporter_BeginOCUnit_SDKNameKey: testableBuildSettings[@"SDK_NAME"],
                                        kReporter_BeginOCUnit_TestTypeKey: isApplicationTest ? @"application-test" : @"logic-test",
                                        kReporter_BeginOCUnit_GCEnabledKey: @(garbageCollectionEnabled),
                                        };

      NSMutableDictionary *beginEvent = [NSMutableDictionary dictionaryWithDictionary:@{
                                         @"event": kReporter_Events_BeginOCUnit,
                                         }];
      [beginEvent addEntriesFromDictionary:commonEventInfo];
      [reporters makeObjectsPerformSelector:@selector(handleEvent:) withObject:beginEvent];

      NSString *error = nil;
      BOOL configurationSucceeded = [testRunner runTestsWithError:&error];

      if (!configurationSucceeded) {
        succeeded = NO;
      }

      NSMutableDictionary *endEvent = [NSMutableDictionary dictionaryWithDictionary:@{
                                       @"event": kReporter_Events_EndOCUnit,
                                                   kReporter_EndOCUnit_SucceededKey: @(succeeded),
                                               kReporter_EndOCUnit_FailureReasonKey: (error ? error : [NSNull null]),
                                       }];
      [endEvent addEntriesFromDictionary:commonEventInfo];
      [reporters makeObjectsPerformSelector:@selector(handleEvent:) withObject:endEvent];
    }

    for (id reporter in reporters) {
      if ([reporter respondsToSelector:@selector(flush)]) {
        [reporter flush];
      }
    }

    return succeeded;
  };

  return @{kTestableBlock: [[action copy] autorelease],
           kTestableMustRunInMainThread: @(isApplicationTest)};
}

- (BOOL)runTestables:(NSArray *)testables
             testSDK:(NSString *)testSDK
      freshSimulator:(BOOL)freshSimulator
        freshInstall:(BOOL)freshInstall
             options:(Options *)options
    xcodeSubjectInfo:(XcodeSubjectInfo *)xcodeSubjectInfo
{
  NSObject *succeededLock = [[[NSObject alloc] init] autorelease];
  __block BOOL succeeded = YES;

  @autoreleasepool {
    NSMutableArray *blocksToRunInMainThread = [NSMutableArray array];
    NSOperationQueue *operationQueue = [[[NSOperationQueue alloc] init] autorelease];
    if (!self.parallelize) {
      operationQueue.maxConcurrentOperationCount = 1;
    }

    for (NSDictionary *testable in testables) {
      NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        BOOL senTestInvertScope = [testable[@"senTestInvertScope"] boolValue];
        NSString *senTestList = testable[@"senTestList"];

        NSArray *reporters = options.reporters;
        if (self.parallelize) {
          // parallel execution will cause reporters to be buffered and flushed
          // atomically at end of test to prevent interleaved output.
          NSMutableArray *bufferedReporters = [NSMutableArray arrayWithCapacity:reporters.count];
          for (Reporter *reporter in reporters) {
            [bufferedReporters addObject:[BufferedReporter bufferedReporterWithReporter:reporter]];
          }
          reporters = bufferedReporters;
        }

        NSDictionary *action = [self blockForTestable:testable
                                            reporters:reporters
                                              objRoot:xcodeSubjectInfo.objRoot
                                              symRoot:xcodeSubjectInfo.symRoot
                                    sharedPrecompsDir:xcodeSubjectInfo.sharedPrecompsDir
                                       xcodeArguments:[options commonXcodeBuildArgumentsIncludingSDK:NO]
                                              testSDK:testSDK
                                       freshSimulator:freshSimulator
                                         freshInstall:freshInstall
                                          senTestList:senTestList
                                   senTestInvertScope:senTestInvertScope];

        BOOL (^block)() = action[kTestableBlock];
        if ([action[kTestableMustRunInMainThread] boolValue]) {
          @synchronized(blocksToRunInMainThread) {
            [blocksToRunInMainThread addObject:block];
          }
        } else {
          if (!block()) {
            @synchronized(succeededLock) {
              succeeded = NO;
            }
          }
        }
      }];

      [operationQueue addOperation:operation];
    }

    [operationQueue waitUntilAllOperationsAreFinished];

    for (BOOL (^block)() in blocksToRunInMainThread) {
      if (!block()) {
        succeeded = NO;
      }
    }
  }

  return succeeded;
}

- (BOOL)validateSDK:(NSString *)sdk
{
  NSMutableArray *supportedTestSDKs = [NSMutableArray array];
  for (NSString *sdk in [GetAvailableSDKsAndAliases() allKeys]) {
    if ([sdk hasPrefix:@"iphonesimulator"] || [sdk hasPrefix:@"macosx"]) {
      [supportedTestSDKs addObject:sdk];
    }
  }

  // We'll only test the iphonesimulator SDKs right now.
  return [supportedTestSDKs containsObject:sdk];
}

@end
