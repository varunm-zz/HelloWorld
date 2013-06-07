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

#import <Foundation/Foundation.h>

NSDictionary *BuildSettingsFromOutput(NSString *output);
NSString *AbsoluteExecutablePath(void);
NSString *PathToXCToolBinaries(void);
NSString *XcodeDeveloperDirPath(void);
NSString *MakeTempFileWithPrefix(NSString *prefix);
NSDictionary *GetAvailableSDKsAndAliases();
BOOL IsRunningUnderTest();

/**
 Launches a task that will invoke xcodebuild.  It will automatically feed
 build events to the provided reporters.
 
 Returns YES if xcodebuild succeeded.  If it fails, errorMessage and errorCode
 will be populated.
 */
BOOL LaunchXcodebuildTaskAndFeedEventsToReporters(NSTask *task,
                                                  NSArray *reporters,
                                                  NSString **errorMessage,
                                                  long long *errorCode);

/**
 Sends a 'begin-xcodebuild' event, runs xcodebuild, then sends an
 'end-xcodebuild' event.
 */
BOOL RunXcodebuildAndFeedEventsToReporters(NSArray *arguments,
                                           NSString *command,
                                           NSString *title,
                                           NSArray *reporters);
