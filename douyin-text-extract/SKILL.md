---
name: douyin-text-extract
description: 抖音视频语音转文字完整流程。自动启动抖音MCP服务、下载视频、提取音频、智能切片、识别文字并保存。
metadata:
  openclaw:
    triggers:
      - 抖音文本提取
      - 抖音语音转文字
      - douyin text extract
      - 抖音视频识别
---

# douyin-text-extract — 抖音视频语音转文字

> 一键提取抖音视频中的语音文字，自动处理所有环节

## 功能流程

1. **启动抖音 MCP 服务** - 确保 douyin-mcp-server 正常运行
2. **获取视频信息** - 解析抖音链接获取视频元数据
3. **下载无水印视频** - 获取并下载视频
4. **提取音频** - 从视频中提取音频
5. **智能切片** - 音频太长时自动分割成小片段
6. **语音识别** - 调用 ASR 识别文字
7. **保存结果** - 整合所有文字保存到文件

## 使用方式

```bash
# 基本用法
douyin-text-extract <抖音链接>

# 指定保存目录
douyin-text-extract <抖音链接> /保存/路径

# 指定 API Key
DASHSCOPE_API_KEY=your_api_key douyin-text-extract <抖音链接>
```

## 示例

```
douyin-text-extract https://v.douyin.com/phPXmZEVurY/
douyin-text-extract https://v.douyin.com/phPXmZEVurY/ /home/admin/europe/rome
```

## 环境要求

- `mcporter` 已安装
- `douyin-mcp-server` 可用
- `ffmpeg` 用于音视频处理
- `DASHSCOPE_API_KEY` 环境变量（阿里云百炼 API Key）

## 输出文件

- `{视频标题}.txt` - 识别的文字内容
- `{视频标题}.mp4` - 下载的视频文件
- `{视频标题}.mp3` - 提取的音频文件

## 技术细节

### API Key 设置

需要设置阿里云百炼 API Key：
```bash
export DASHSCOPE_API_KEY="sk-xxx"
```

或使用参数传入。

### 音频切片策略

- 单个音频文件 < 20MB 直接识别
- 超过则自动切片为 60 秒片段
- 识别完成后合并所有文字

### 支持的格式

- 输入：抖音分享链接
- 输出：UTF-8 编码的 TXT 文件
