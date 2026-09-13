#ifndef SCRIBBLETEST_H
#define SCRIBBLETEST_H

#include "scribbledoc.h"
#include "bookmarkview.h"

class ScribbleTest
{
friend class ScribbleApp;
public:
  ScribbleTest(const std::string &path);
  ScribbleTest(ScribbleDoc* sd, BookmarkView* bv, ScribbleMode* sm);
  ~ScribbleTest();

  void runAll(bool runsynctest = false);
  void performanceTest();
  void inputTest();
  void syncSlaveMsg(std::string msg, int level);

  // result string to be read by caller
  std::string resultStr;

  static bool exitAfterTest;

  // conventional process exit statuses for --test runs (detailed counts in resultStr
  //  and in the machine-readable summary file written next to the output files)
  enum TestExitStatus {
    EXIT_OK = 0,
    EXIT_TESTS_FAILED = 1,
    EXIT_THUMBS_FAILED = 2,
    EXIT_EXECUTION_ERROR = 3  // wrong number of tests executed (e.g. none)
  };

private:
  ScribbleConfig* scribbleConfig;
  ScribbleDoc* scribbleDoc;
  ScribbleArea* scribbleArea;
  ScribbleMode* scribbleMode;
  BookmarkView* bookmarkArea;
  Image* screenImg;
  Painter* screenPaint;
  Rect screenRect;
  // outPath is the writable directory for _out files and diffs; refPath is where
  //  _in/_ref inputs are read from (SCRIBBLE_TEST_OUT env var makes them differ)
  std::string outPath;
  std::string refPath;
  int nFailed;

  // shared whiteboard testing
  pugi::xml_document swbXML;
  ScribbleTest* syncSlave;
  int syncTestNum;
  bool waitForSyncDone;
  void startSyncTest(int testnum);
  void waitForSync();
  void checkStrokeMap(ScribbleDoc* doc, const char* msg);

  static const int pen = INPUTSOURCE_PEN;
  static const int press = INPUTEVENT_PRESS;
  static const int release = INPUTEVENT_RELEASE;
  void undo() { scribbleDoc->doCommand(ID_UNDO); }
  void redo() { scribbleDoc->doCommand(ID_REDO); }
  void doCommand(int cmd) { scribbleDoc->doCommand(cmd); }
  bool testCompareFiles(const char* f1, const char* f2, bool svgonly = false);
  static bool thumbnailsCloseEnough(const Image& ref, const Image& out, int maxDelta, double maxFracChanged);
  static bool writeSummaryFile(const std::string& filename, const std::string& body);
  void ie(Dim x, Dim y, Dim p, int src, int ev = 0, int mm = 0);
  void mtinput(inputevent_t ev1, Dim x1, Dim y1, inputevent_t ev2, Dim x2, Dim y2);
  void ss(Dim offset);
  void s1(Dim xoffset, Dim yoffset);
  void s2(Dim xoffset, Dim yoffset);
  void s3(Dim xoffset, Dim yoffset);
  void f2(Dim xoffset, Dim yoffset);
  void hr(Dim xoffset, Dim yoffset);
  void s3();
  void s4();

  void test0();
  void test1();
  void test2();
  void test3();
  void test4();
  void test5();
  void test6();
  void test7();
  void test8();
  void test9();
  void test10();
  void test11();
  void test12();
  void test13();
  void test14();
  void test15();
  void test16();
  void synctest01();
  void synctest01slave1();
  void synctest01slave2();
};

#endif
