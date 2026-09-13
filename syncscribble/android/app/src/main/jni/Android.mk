#include $(call all-subdir-makefiles)

# Note that symlinking source dirs is a terrible idea which can create a huge mess when trying to open files,
#  esp. when debugging
WRITE_LOCAL_PATH := $(call my-dir)
# Keep the Android build relocatable: this directory is
# syncscribble/android/app/src/main/jni: five levels below syncscribble/ and
# six levels below the repository root, where SDL/ is a sibling of syncscribble/.
include $(WRITE_LOCAL_PATH)/../../../../../../SDL/Android.mk
# SDL's Android.mk assigns LOCAL_PATH, so use our saved app path here.
include $(WRITE_LOCAL_PATH)/../../../../../Makefile
