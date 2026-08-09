#!/bin/sh

# merman 0.7.0's prebuilt macOS dylib was published with its CI checkout as
# LC_ID_DYLIB. Anything linked against it therefore records a path under
# /Users/runner/work and builds successfully but fails at launch. Repair only
# artifacts inside this app bundle; never mutate the shared Pub cache.

set -eu

app_dir="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
macos_dir="${app_dir}/Contents/MacOS"
frameworks_dir="${app_dir}/Contents/Frameworks"
ffi_name="libmerman_ffi.dylib"
ffi_path="${frameworks_dir}/${ffi_name}"
portable_name="@rpath/${ffi_name}"

if [ ! -f "${ffi_path}" ]; then
  exit 0
fi

install_name_tool -id "${portable_name}" "${ffi_path}"

patch_dependency() {
  binary="$1"
  if [ ! -f "${binary}" ]; then
    return
  fi

  dependencies="$(otool -L "${binary}" | awk '/\/libmerman_ffi\.dylib/ { print $1 }')"
  for dependency in ${dependencies}; do
    if [ "${dependency}" != "${portable_name}" ]; then
      install_name_tool -change "${dependency}" "${portable_name}" "${binary}"
    fi
  done
}

patch_dependency "${macos_dir}/${PRODUCT_NAME}"
patch_dependency "${macos_dir}/${PRODUCT_NAME}.debug.dylib"
patch_dependency "${frameworks_dir}/merman.framework/Versions/A/merman"

# Fail the build instead of producing another app that only crashes at launch.
for binary in \
  "${macos_dir}/${PRODUCT_NAME}" \
  "${macos_dir}/${PRODUCT_NAME}.debug.dylib" \
  "${frameworks_dir}/merman.framework/Versions/A/merman"; do
  if [ -f "${binary}" ] && otool -L "${binary}" | grep -q '/Users/runner/.*/libmerman_ffi\.dylib'; then
    echo "error: merman still contains a non-portable install name in ${binary}" >&2
    exit 1
  fi
done

# CocoaPods has already signed embedded frameworks at this point. Changing a
# Mach-O load command invalidates that signature, so re-sign the two nested
# code objects with the identity selected by Xcode. The outer app/debug dylib
# are signed by the remaining Xcode build steps.
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
  signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [ -z "${signing_identity}" ]; then
    signing_identity="-"
  fi

  codesign --force --sign "${signing_identity}" --timestamp=none "${ffi_path}"

  merman_framework="${frameworks_dir}/merman.framework"
  if [ -d "${merman_framework}" ]; then
    codesign --force --sign "${signing_identity}" --timestamp=none \
      "${merman_framework}"
  fi
fi
