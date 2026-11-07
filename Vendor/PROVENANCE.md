# 上游来源

- WLOC: https://github.com/Yu9191/wloc ，dist/wloc.js 原样内嵌，AGPL-3.0，许可证见 WLOC-LICENSE。
- WLOCRules: https://github.com/spirit-n/WLOCRules ，rules.c / rules.h 和 root helper 启动部分。仓库未提供明确许可证；本地个人验证用途，公开分发前需确认授权。
- 修改：备份完成后将备份库切换为 DELETE journal 模式，使 WAL 源库的备份可独立只读打开；保留匹配域名范围；增加实际表结构检查、分版本备份及元信息、新版本与本机 v131 基准的完整策略比对、版本和指纹绑定的明确确认。
- 不包含上游可执行程序，不远程下载和执行脚本。构建时源文件固定在 Vendor 中。
