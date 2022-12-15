# windows-archive-tool

This is a tool to perform basic file moving commands and mainly for backing up and merging data

The test1 and test2 directories are for testing the script. They are set up to make useful output when test2 is source and test1 is destination. This will allow one to test the script in their environment before running and possibly making changes they didnt want to files.

Usage:
```
windows-archive-tool.ps1 <source dir> <destination dir> <logging dir>
```

Note: **source dir** acts as the new directory and **destination dir** acts as the original directory when running comparisions
