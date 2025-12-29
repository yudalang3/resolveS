# resolveS 项目规则

## 版本管理

当版本变更时，**三个主程序都必须同步更新版本号**：
- `bin/resolveS`
- `bin/resolveS_fast`
- `bin/resolveS_singlePrecise`

版本号位置：各脚本的 `print_usage()` 函数中的 `This is resolveS* version x.x.x`

## 文档更新

README 更新时，**中英文都要同步更新**：
- `README.md`（英文）
- `README_zh.md`（中文）

## 脚本命名规范

| 前缀 | 用途 |
|------|------|
| `default_` | 默认版本（双端比对）使用的脚本 |
| `fast_` | 快速版本（单端比对）使用的脚本 |
| `precise_` | 精确版本（1M递增分析）使用的脚本 |

## 共用组件

- `default_align_by_bowtie2.sh` - resolveS 和 resolveS_singlePrecise 共用
- `fast_check_strand.py` - 所有版本共用的链分析模块

## 中间文件

运行时产生的临时文件（使用 `-d` 参数可保留）：
- `resolveS.sam` - bowtie2 比对输出
- `log.raw.SAM.counts.txt` - 计数结果（可通过 `-c` 自定义）

## 文件格式

所有文本文件使用 **LF** 换行符（非 CRLF）
