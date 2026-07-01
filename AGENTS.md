# resolveS 项目规则

## 版本管理

当版本变更时，必须检查主程序版本号：
- `bin/resolveS`

版本号位置：`print_usage()` 函数中的 `This is resolveS version x.x.x`

**重要**：每次 commit 时都要检查是否需要更新版本号。

## 文档更新

README 更新时，**中英文都要同步更新**：
- `README.md`（英文）
- `README_zh.md`（中文）

## 脚本命名规范

| 前缀 | 用途 |
|------|------|
| `default_` | 默认版本（双端比对）使用的脚本 |

## 共用组件

- `default_counting_withChrom.pl` - Perl 版链分析模块

## 中间文件

运行时产生的临时文件（使用 `-d` 参数可保留）：
- `resolveS.sam` - bowtie2 比对输出

## 文件格式

所有文本文件使用 **LF** 换行符（非 CRLF）
