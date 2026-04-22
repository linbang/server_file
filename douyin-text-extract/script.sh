#!/bin/bash
#
# 抖音视频语音转文字完整流程
# 功能：启动MCP → 下载视频 → 提取音频 → 切片 → 语音识别 → 保存文字
#

set -e

# 设置 API Key（如果环境变量中未设置）
if [ -z "$DASHSCOPE_API_KEY" ]; then
    # 尝试从文件读取
    if [ -f "$HOME/.openclaw/openclaw.json" ]; then
        API_KEY_FROM_FILE=$(grep -o '"dashscope"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.openclaw/openclaw.json" 2>/dev/null | head -1 | grep -o 'sk-[^"]*')
        if [ -n "$API_KEY_FROM_FILE" ]; then
            export DASHSCOPE_API_KEY="$API_KEY_FROM_FILE"
        fi
    fi
    # 如果还没有，使用用户提供的 key（如果有）
    if [ -z "$DASHSCOPE_API_KEY" ]; then
        export DASHSCOPE_API_KEY="sk-64a79c1ae0fa4a2cbdbdd7e6fe1afb5a"
    fi
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认参数
DOUYIN_LINK=""
SAVE_DIR="${2:-/tmp}"
API_KEY="${DASHSCOPE_API_KEY:-}"

# 检查参数
if [ -z "$1" ]; then
    echo -e "${RED}用法: douyin-text-extract <抖音链接> [保存目录]${NC}"
    echo -e "${YELLOW}示例: douyin-text-extract https://v.douyin.com/xxx/ /home/admin/videos${NC}"
    exit 1
fi

DOUYIN_LINK="$1"
if [ -n "$2" ]; then
    SAVE_DIR="$2"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  抖音视频语音转文字${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "📎 链接: ${DOUYIN_LINK}"
echo -e "📁 保存目录: ${SAVE_DIR}"
echo ""

# Step 1: 启动抖音 MCP 服务
echo -e "${YELLOW}▶ Step 1: 检查/启动抖音 MCP 服务...${NC}"
mcporter list | grep -q "douyin.*online" || {
    # 尝试修复配置并重启
    if ! grep -q "douyin-mcp-server" ~/.openclaw/workspace/config/mcporter.json 2>/dev/null; then
        sed -i 's/"command": "mcp-server-douyin"/"command": "douyin-mcp-server"/' ~/.openclaw/workspace/config/mcporter.json 2>/dev/null || true
    fi
}
mcporter list | grep "douyin"
echo -e "${GREEN}✓ MCP 服务状态检查完成${NC}"
echo ""

# Step 2: 获取视频信息
echo -e "${YELLOW}▶ Step 2: 获取视频信息...${NC}"
VIDEO_INFO=$(mcporter call 'douyin.parse_douyin_video_info' "share_link:$DOUYIN_LINK" 2>&1)

if echo "$VIDEO_INFO" | grep -q '"status": "success"'; then
    VIDEO_ID=$(echo "$VIDEO_INFO" | grep -o '"video_id": "[^"]*"' | head -1 | cut -d'"' -f4)
    TITLE=$(echo "$VIDEO_INFO" | grep -o '"title": "[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${GREEN}✓ 视频ID: ${VIDEO_ID}${NC}"
    echo -e "${GREEN}✓ 标题: ${TITLE}${NC}"
else
    echo -e "${RED}✗ 获取视频信息失败${NC}"
    echo "$VIDEO_INFO"
    exit 1
fi

# 清理标题中的非法字符
SAFE_TITLE=$(echo "$TITLE" | sed 's/[\\/:*?"<>|]/_/g' | cut -c1-50)
echo ""

# Step 3: 获取下载链接
echo -e "${YELLOW}▶ Step 3: 获取下载链接...${NC}"
DOWNLOAD_INFO=$(mcporter call 'douyin.get_douyin_download_link' "share_link:$DOUYIN_LINK" 2>&1)
DOWNLOAD_URL=$(echo "$DOWNLOAD_INFO" | grep -o '"download_url": "[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}✗ 获取下载链接失败${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 获取下载链接成功${NC}"
echo ""

# Step 4: 下载视频
echo -e "${YELLOW}▶ Step 4: 下载视频...${NC}"
mkdir -p "$SAVE_DIR"
VIDEO_FILE="$SAVE_DIR/${SAFE_TITLE}.mp4"

if [ -f "$VIDEO_FILE" ]; then
    echo -e "${YELLOW}⚠ 视频已存在，跳过下载${NC}"
else
    echo "正在下载视频..."
    curl -L "$DOWNLOAD_URL" -o "$VIDEO_FILE" --progress-bar 2>&1 | tail -5
    
    if [ ! -s "$VIDEO_FILE" ]; then
        echo -e "${RED}✗ 视频下载失败${NC}"
        exit 1
    fi
fi

VIDEO_SIZE=$(du -h "$VIDEO_FILE" | cut -f1)
echo -e "${GREEN}✓ 视频下载完成 (${VIDEO_SIZE})${NC}"
echo ""

# Step 5: 提取音频
echo -e "${YELLOW}▶ Step 5: 提取音频...${NC}"
AUDIO_FILE="$SAVE_DIR/${SAFE_TITLE}.mp3"

if [ -f "$AUDIO_FILE" ]; then
    echo -e "${YELLOW}⚠ 音频已存在，跳过提取${NC}"
else
    # 提取音频为MP3
    ffmpeg -i "$VIDEO_FILE" -vn -acodec libmp3lame -q:a 2 -y "$AUDIO_FILE" 2>&1 | tail -3
    
    if [ ! -s "$AUDIO_FILE" ]; then
        echo -e "${RED}✗ 音频提取失败${NC}"
        exit 1
    fi
fi

AUDIO_SIZE=$(du -h "$AUDIO_FILE" | cut -f1)
echo -e "${GREEN}✓ 音频提取完成 (${AUDIO_SIZE})${NC}"
echo ""

# Step 6: 音频切片（如需要）
echo -e "${YELLOW}▶ Step 6: 检查音频大小并切片...${NC}"
AUDIO_BYTES=$(stat -c%s "$AUDIO_FILE" 2>/dev/null || stat -f%z "$AUDIO_FILE" 2>/dev/null)
MAX_SIZE=20971520  # 20MB

if [ "$AUDIO_BYTES" -gt "$MAX_SIZE" ]; then
    echo -e "${YELLOW}⚠ 音频文件较大 (${AUDIO_BYTES} bytes)，进行切片处理...${NC}"
    
    # 创建分片目录
    SLICE_DIR="$SAVE_DIR/${SAFE_TITLE}_slices"
    mkdir -p "$SLICE_DIR"
    
    # 按60秒分片
    ffmpeg -i "$AUDIO_FILE" -f segment -segment_time 60 -c copy "$SLICE_DIR/part%02d.mp3" -y 2>&1 | tail -3
    
    SLICE_COUNT=$(ls -1 "$SLICE_DIR"/*.mp3 2>/dev/null | wc -l)
    echo -e "${GREEN}✓ 已切片为 ${SLICE_COUNT} 个文件${NC}"
    SLICES="$SLICE_DIR/part%02d.mp3"
else
    echo -e "${GREEN}✓ 音频文件较小，直接识别${NC}"
    SLICES="$AUDIO_FILE"
fi
echo ""

# Step 7: 语音识别
echo -e "${YELLOW}▶ Step 7: 语音识别...${NC}"
OUTPUT_FILE="$SAVE_DIR/${SAFE_TITLE}.txt"

# 写入文件头
cat > "$OUTPUT_FILE" << EOF
# ${TITLE}

- 视频链接: ${DOUYIN_LINK}
- 视频ID: ${VIDEO_ID}
- 提取日期: $(date '+%Y-%m-%d %H:%M:%S')

---

EOF

# 检查API Key
if [ -z "$API_KEY" ]; then
    echo -e "${YELLOW}⚠ 未设置 DASHSCOPE_API_KEY，尝试从环境变量获取...${NC}"
    export DASHSCOPE_API_KEY="${API_KEY}"
fi

# 使用 Python 直接调用 ASR
python3 << PYTHON_EOF > /tmp/asr_log.txt 2>&1
import os
import glob
import sys

# 设置 API Key
api_key = os.environ.get('DASHSCOPE_API_KEY', '')
if not api_key:
    # 尝试从配置读取
    try:
        with open(os.path.expanduser('~/.openclaw/openclaw.json'), 'r') as f:
            import json
            config = json.load(f)
            api_key = config.get('keys', {}).get('dashscope', '')
            if api_key:
                os.environ['DASHSCOPE_API_KEY'] = api_key
    except:
        pass

if not api_key:
    print("ERROR: 未设置 DASHSCOPE_API_KEY", file=sys.stderr)
    sys.exit(1)

from douyin_mcp_server.asr_module import QwenASR

asr = QwenASR(api_key=api_key, model="qwen3-asr-flash-filetrans")

# 获取所有音频文件
audio_files = []
if "$SLICES" == "$AUDIO_FILE":
    audio_files = ["$AUDIO_FILE"]
else:
    audio_files = sorted(glob.glob("$SLICE_DIR" + "/*.mp3"))

print(f"开始识别 {len(audio_files)} 个音频文件...")

all_text = []
for filepath in audio_files:
    filename = os.path.basename(filepath)
    print(f"识别中: {filename}")
    
    result = asr.recognize_file(filepath)
    if result.get('success'):
        text = result.get('text', '')
        all_text.append(text)
        print(f"✓ {filename}: {len(text)} 字")
    else:
        print(f"✗ {filename}: {result.get('error')}")

# 保存结果
output_path = "$OUTPUT_FILE"
with open(output_path, 'a', encoding='utf-8') as f:
    f.write('\n\n'.join(all_text))

total = sum(len(t) for t in all_text)
print(f"完成! 共 {len(all_text)} 段, {total} 字")
print(f"保存到: {output_path}")
PYTHON_EOF

ASR_RESULT=$(cat /tmp/asr_log.txt)
if echo "$ASR_RESULT" | grep -q "完成"; then
    echo -e "${GREEN}✓ 语音识别成功${NC}"
    echo "$ASR_RESULT"
else
    echo -e "${RED}✗ 语音识别失败${NC}"
    echo "$ASR_RESULT"
    
    # 备用方案：尝试使用 mcporter
    echo -e "${YELLOW}尝试备用方案 (mcporter)...${NC}"
    
    if [ "$SLICES" == "$AUDIO_FILE" ]; then
        RESULT=$(mcporter call --timeout 180 'douyin.recognize_audio_file' "file_path:$AUDIO_FILE" 2>&1)
        if echo "$RESULT" | grep -q '"status": "success"'; then
            TEXT=$(echo "$RESULT" | grep -o '"text": "[^"]*"' | sed 's/"text": "//' | sed 's/"$//')
            echo "$TEXT" >> "$OUTPUT_FILE"
            echo -e "${GREEN}✓ 备用方案成功${NC}"
        fi
    fi
fi
echo ""

# Step 8: 完成
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 完成!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "📄 文字保存位置: ${OUTPUT_FILE}"
echo -e "🎬 视频保存位置: ${VIDEO_FILE}"
echo -e "🎵 音频保存位置: ${AUDIO_FILE}"
echo ""

# 显示结果预览
echo -e "${YELLOW}文字预览 (前500字):${NC}"
head -c 500 "$OUTPUT_FILE"
echo ""
echo ""
