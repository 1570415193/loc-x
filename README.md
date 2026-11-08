# loc x

## 使用条件

- iPhone 7 / iOS 15.8.5，使用 TrollStore 安装。
- 需要联网使用高德街道地图和地点搜索。首次使用时，按系统提示安装并信任证书、授权 VPN 配置。
- 本工具通过本机 VPN 重写支持的网络定位请求，不替换 GPS，也不保证影响所有 App。
- 普通 `.tipa` 由 TrollStore 安装；若设备上的 `Install ldid` 不可用，可在 Mac 本地生成预处理签名包。

## 使用步骤

1. 在地图上点选位置，或搜索地点并从下拉候选中选择。
2. 点“修改”，按提示完成系统授权；等待 App 确认结果。
3. 成功后按提示到系统设置中关闭并重新打开“定位服务”，再检查目标 App。

## 本地编译

需要 macOS、Xcode 命令行工具和 OpenSSL 3。在项目目录运行：

```sh
WLOC_KEYS_DIR=/path/to/private/keys python3 build.py
```

安装包生成在 `build/`。更新时复用同一个私钥目录，以保留证书身份；私钥目录不要提交到仓库。地图及重写测试可运行：

```sh
node Tests/test_map.cjs
python3 Tests/test_rewrite.py
python3 Tests/test_control.py
```

## 引用仓库原理

- [Yu9191/wloc](https://github.com/Yu9191/wloc)：参考其通过本机 VPN 代理定位服务 HTTPS 请求，并重写定位响应的工作方式。
- [spirit-n/WLOCRules](https://github.com/spirit-n/WLOCRules)：参考其定位规则检查和定点修改思路；本项目保留独立的兼容性检查、本机备份与恢复保护。
- [Leaflet](https://github.com/Leaflet/Leaflet)：用于显示地图；坐标显示换算沿用 wloc 所用的 GCJ-02 转换思路。

## 致谢

感谢 wloc、WLOCRules 与 Leaflet 项目及其贡献者。各项目版权和许可证按各自仓库及 `Vendor/` 中的声明保留。
