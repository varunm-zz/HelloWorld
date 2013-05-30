#!/bin/sh
# Run the unit tests in this test bundle.
#"${PROJECT_DIR}/XcodeScripts/RunPlatformUnitTests"
if [ -z "${WANT_IOS_SIM}" ]
then
#   Running under xcodebuild, so use ios-sim installed from Homebrew into /usr/local/bin/ios-sim
killall -m -KILL "iPhone Simulator" || true
our_test_bundle_path=$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.$WRAPPER_EXTENSION
our_env=("--setenv" "DYLD_INSERT_LIBRARIES=/../../Library/PrivateFrameworks/IDEBundleInjection.framework/IDEBundleInjection")
our_env=("${our_env[@]}" "--setenv" "XCInjectBundle=${our_test_bundle_path}")
our_env=("${our_env[@]}" "--setenv" "XCInjectBundleInto=${TEST_HOST}")
our_app_location="$(dirname "${TEST_HOST}")"
/usr/local/bin/ios-sim launch "${our_app_location}" "${our_env[@]}" --args -SenTest All "${our_test_bundle_path}" --exit
killall -m -KILL "iPhone Simulator" || true
exit 0
else
#   Running under Xcode
"${DEVELOPER_TOOLS_DIR}/RunUnitTests"
fi

