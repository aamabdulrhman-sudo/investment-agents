#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  وكلاة الذكاء الاستثماري — التثبيت الشامل + التشغيل التلقائي
# ═══════════════════════════════════════════════════════════
set -e

INSTALL_DIR="${1:-$HOME/investment-agents}"
REPO_BASE="https://github.com/aamabdulrhman-sudo"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}   وكلاة الذكاء الاستثماري — التثبيت الشامل${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

# ── 1. فحص والأدوات ──
info "فحص المتطلبات..."

for cmd in python3 git curl; do
    if ! command -v $cmd &>/dev/null; then
        warn "$cmd غير متوفر — محاولة التثبيت..."
        if command -v apt &>/dev/null; then
            sudo apt update -qq && sudo apt install -y -qq $cmd
        elif command -v pkg &>/dev/null; then
            pkg update -y && pkg install -y $cmd
        elif command -v yum &>/dev/null; then
            sudo yum install -y $cmd
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm $cmd
        fi
    fi
done
log "المتطلبات جاهزة: $(python3 --version 2>&1)"

# ── 2. استنساخ المشاريع ──
mkdir -p "$INSTALL_DIR"

clone_if_needed() {
    local repo="$1" dir="$2"
    if [ -d "$INSTALL_DIR/$dir/.git" ]; then
        log "$dir موجود — git pull..."
        cd "$INSTALL_DIR/$dir" && git pull --quiet 2>/dev/null || true
    else
        info "استنساخ $repo..."
        git clone --quiet "$REPO_BASE/$repo.git" "$INSTALL_DIR/$dir"
        log "تم: $dir"
    fi
}

clone_if_needed "saudi-market-news-agent"  "saudi-market-news-agent"
clone_if_needed "market-analyst-agent"     "market-analyst-agent"
clone_if_needed "investment-strategy-agent" "investment-strategy-agent"
clone_if_needed "executive-trading-agent"  "executive-trading-agent"

# ── 3. إنشاء scripts ──

# ── start.sh ──
cat > "$INSTALL_DIR/start.sh" << 'STARTEOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

mkdir -p "$DIR/data/logs"

is_running() {
    local pidfile="$DIR/data/${1}.pid"
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$pidfile"
    fi
    return 1
}

start_agent() {
    local name="$1" dir="$2" cmd="$3" port="$4" extra_env="${5:-}"
    local pidfile="$DIR/data/${name}.pid"
    local logfile="$DIR/data/logs/${name}.log"

    if is_running "$name"; then
        warn "$name شغّال مسبقاً (PID $(cat "$pidfile"))"
        return
    fi

    info "تشغيل $name على :$port ..."
    cd "$DIR/$dir"
    if [ -n "$extra_env" ]; then
        nohup env $extra_env python3 "$cmd" >> "$logfile" 2>&1 &
    else
        nohup python3 "$cmd" >> "$logfile" 2>&1 &
    fi
    echo $! > "$pidfile"

    for i in $(seq 1 20); do
        if curl -s --max-time 1 "http://127.0.0.1:$port/api/status" 2>/dev/null | grep -q '"ok":true'; then
            log "$name جاهز ✅"
            return
        fi
        sleep 1
    done
    warn "$name قد يحتاج وقتاً إضافياً"
}

# تشغيل بالترتيب
start_agent "news"      "saudi-market-news-agent"  "news.py"       8081
sleep 2
start_agent "analyst"   "market-analyst-agent"     "analyst.py"    8084 "NEWS_AGENT_URL=http://127.0.0.1:8081"
sleep 2
start_agent "strategy"  "investment-strategy-agent" "strategy.py"  8085
sleep 2
start_agent "executive" "executive-trading-agent"  "executive.py"  8086

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  جميع الوكلاء شغّالين!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "  الأخبار        → http://localhost:8081"
echo "  محلل السوق     → http://localhost:8084"
echo "  استراتيجية     → http://localhost:8085"
echo "  التنفيذ        → http://localhost:8086"
echo ""
echo "  logs: $DIR/data/logs/"
echo "  Ctrl+C لإيقاف الكل"
echo ""
while true; do sleep 60; done
STARTEOF
chmod +x "$INSTALL_DIR/start.sh"

# ── stop.sh ──
cat > "$INSTALL_DIR/stop.sh" << 'STOPEOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "إيقاف جميع الوكلاء..."
for pidfile in "$DIR"/data/*.pid; do
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null && rm -f "$pidfile"
done
pkill -f "news.py" 2>/dev/null || true
pkill -f "analyst.py" 2>/dev/null || true
pkill -f "strategy.py" 2>/dev/null || true
pkill -f "executive.py" 2>/dev/null || true
echo "✓ تم الإيقاف"
STOPEOF
chmod +x "$INSTALL_DIR/stop.sh"

# ── status.sh ──
cat > "$INSTALL_DIR/status.sh" << 'STATUSEOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════"
echo "  حالة الوكلاء"
echo "═══════════════════════════════════════════════════"
check() {
    local name="$1" port="$2"
    if curl -s --max-time 2 "http://127.0.0.1:$port/api/status" 2>/dev/null | grep -q '"ok":true'; then
        echo "  ✅ $name  →  :$port  شغّال"
    else
        echo "  ❌ $name  →  :$port  متوقف"
    fi
}
check "وكيل الأخبار"         8081
check "محلل السوق"           8084
check "استراتيجية الاستثمار" 8085
check "وكيل التنفيذ"         8086
echo "═══════════════════════════════════════════════════"
STATUSEOF
chmod +x "$INSTALL_DIR/status.sh"

# ── watchdog.sh — ي restarting أي وكيل مطفى ──
cat > "$INSTALL_DIR/watchdog.sh" << 'WDEOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"

check_and_restart() {
    local name="$1" dir="$2" cmd="$3" port="$4" extra_env="${5:-}"
    local pidfile="$DIR/data/${name}.pid"

    # تحقق هل الوكيل شغّال
    if curl -s --max-time 2 "http://127.0.0.1:$port/api/status" 2>/dev/null | grep -q '"ok":true'; then
        return
    fi

    echo "[$(date '+%H:%M:%S')] $name متوقف — إعادة التشغيل..."

    # تنظيف_pid القديم
    rm -f "$pidfile"

    cd "$DIR/$dir"
    if [ -n "$extra_env" ]; then
        nohup env $extra_env python3 "$cmd" >> "$DIR/data/logs/${name}.log" 2>&1 &
    else
        nohup python3 "$cmd" >> "$DIR/data/logs/${name}.log" 2>&1 &
    fi
    echo $! > "$pidfile"
    echo "[$(date '+%H:%M:%S')] $name أُعيد تشغيله (PID $!)"
}

while true; do
    check_and_restart "news"      "saudi-market-news-agent"   "news.py"       8081
    sleep 5
    check_and_restart "analyst"   "market-analyst-agent"      "analyst.py"    8084 "NEWS_AGENT_URL=http://127.0.0.1:8081"
    sleep 5
    check_and_restart "strategy"  "investment-strategy-agent"  "strategy.py"   8085
    sleep 5
    check_and_restart "executive" "executive-trading-agent"   "executive.py"  8086
    sleep 60
done
WDEOF
chmod +x "$INSTALL_DIR/watchdog.sh"

# ── 4. إعداد التشغيل التلقائي بعد إعادة التشغيل ──
info "إعداد التشغيل التلقائي..."

# ── الطريقة الأولى: crontab ──
start_script_path="$INSTALL_DIR/start.sh"
(crontab -l 2>/dev/null | grep -v "investment-agents"; echo "@reboot sleep 15 && $start_script_path > $INSTALL_DIR/data/logs/startup.log 2>&1 &") | crontab -
log "تم إضافة مهمة crontab للتشغيل عند البوت"

# ── الطريقة الثانية: ~/.bashrc (كمخزون أمان) ──
AUTOSTART_MARKER="# === investment-agents-autostart ==="
if ! grep -q "$AUTOSTART_MARKER" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << AUTORCEOF

$AUTOSTART_MARKER
# تشغيل تلقائي للوكلاء عند فتح التيرمينال (إذا لم تكن شغّالة)
if [ -f "$INSTALL_DIR/start.sh" ] && ! pgrep -f "news.py" > /dev/null 2>&1; then
    nohup bash "$INSTALL_DIR/start.sh" > "$INSTALL_DIR/data/logs/startup.log" 2>&1 &
    echo "  ✓ وكلاة الاستثمار تُشغّل تلقائياً..."
fi
# === end investment-agents-autostart ===
AUTORCEOF
    log "تم إضافة التشغيل التلقائي إلى ~/.bashrc"
fi

# ── الطريقة الثالثة: profile.d (للppoatches) ──
if [ -d /etc/profile.d ]; then
    cat > /etc/profile.d/investment-agents.sh << PROFILEEOF
# تشغيل تلقائي للوكلاء
if [ -f "$INSTALL_DIR/start.sh" ] && ! pgrep -f "news.py" > /dev/null 2>&1; then
    nohup bash "$INSTALL_DIR/start.sh" > "$INSTALL_DIR/data/logs/startup.log" 2>&1 &
fi
PROFILEEOF
    log "تم إضافة profile.d"
fi

# ── 5. بدء تشغيل فوري ──
info "بدء تشغيل الوكلاء الآن..."
bash "$INSTALL_DIR/start.sh" &
sleep 12

# ── 6. تشغيل الـ watchdog في الخلفية ──
if ! pgrep -f "watchdog.sh" > /dev/null 2>&1; then
    nohup bash "$INSTALL_DIR/watchdog.sh" > "$INSTALL_DIR/data/logs/watchdog.log" 2>&1 &
    echo $! > "$INSTALL_DIR/data/watchdog.pid"
    log "Watchdog شغّال (PID $!) — يراقب الوكلاء كل دقيقة"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  التثبيت والتشغيل اكتمل!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}المجلد:${NC} $INSTALL_DIR/"
echo ""
echo "  start.sh     ← تشغيل يدوي"
echo "  stop.sh      ← إيقاف الكل"
echo "  status.sh    ← فحص الحالة"
echo "  watchdog.sh  ← مراقبة وإعادة تشغيل تلقائية"
echo ""
echo -e "  ${BOLD}التشغيل التلقائي:${NC}"
echo "  ✓ crontab — يعمل عند البوت"
echo "  ✓ bashrc — يعمل عند فتح التيرمينال"
echo "  ✓ watchdog — يعيد تشغيل أي وكيل يطفى"
echo ""
echo "  الأخبار        → http://localhost:8081"
echo "  محلل السوق     → http://localhost:8084"
echo "  استراتيجية     → http://localhost:8085"
echo "  التنفيذ        → http://localhost:8086"
echo ""
