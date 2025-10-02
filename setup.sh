#!/usr/bin/env bash
# This script sets up and deploys a service to Google Cloud Run,
# and sends a notification to Telegram if configured.

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- PROJECT CHECK ---
echo "--- Project Setup ---"

# Attempt to retrieve the current active GCP project
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"

# Check if the project variable is empty
if [[ -z "${PROJECT}" ]]; then
    echo "[ERROR] No active GCP project is set."
    echo "Tip: Please run 'gcloud config set project <YOUR_PROJECT_ID>' to set one."
    exit 1
fi

# Retrieve the project number
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || {
    echo "[ERROR] Failed to get project number for '$PROJECT'. Ensure the ID is correct and you have permission."
    exit 1
}

echo "[SUCCESS] Using project: ${PROJECT} (number: ${PROJECT_NUMBER})"
echo

# --- PROTOCOL SELECTION ---
echo "--- Protocol Selection ---"
echo "Choose protocol:"
echo "  1) Trojan (WS)"
echo "  2) VLESS (WS)"
echo "  3) VLESS (gRPC)"

# Get user input for protocol
read -rp "Enter 1/2/3 [default: 3]: " _opt || true
case "${_opt:-3}" in
    1) PROTO="trojan"    ; IMAGE="docker.io/nynyjk/xray-tg:latest"          ;;
    2) PROTO="vless"     ; IMAGE="docker.io/n4vip/vless:latest"            ;;
    3) PROTO="vlessgrpc" ; IMAGE="docker.io/nynyjk/vless-grpc-restrict:latest"  ;;
    *) PROTO="vlessgrpc" ; IMAGE="docker.io/nynyjk/vless-grpc-restrict:latest"  ;;
esac

echo "Selected Protocol: $PROTO"

# --- DEFAULTS AND CONFIGURATION ---

# Set default values for deployment parameters if they are not already set
SERVICE="${SERVICE:-netflow4mm}"
REGION="${REGION:-us-central1}"
MEMORY="${MEMORY:-16Gi}"
CPU="${CPU:-8}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

# Define all protocol-specific keys
TROJAN_PASS="netflow4mm"
TROJAN_TAG="netflow4mm"
TROJAN_PATH="%2Ftj"

VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_PATH="%2FN4VPN"
VLESS_TAG="N4%20GCP%20VLESS"

VLESSGRPC_UUID="365fcdc9-7a53-4dc9-9ecc-12467e9c729c"
VLESSGRPC_SVC="netflow4mm"
VLESSGRPC_TAG="GCP-VLESS-GRPC"

# --- SERVICE NAME INPUT ---
read -rp "Enter Cloud Run service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"

# --- SUMMARY ---
echo
echo "--- Deployment Summary ---"
echo "Project ID : ${PROJECT}"
echo "Project No.: ${PROJECT_NUMBER}"
echo "Region     : ${REGION}"
echo "Service    : ${SERVICE}"
echo "Protocol   : ${PROTO}"
echo "Image      : ${IMAGE}"
echo "Memory     : ${MEMORY} | CPU: ${CPU}"
echo "Timeout    : ${TIMEOUT}s | Port: ${PORT}"
echo "--------------------------"
echo

# --- ENABLE APIS & DEPLOY ---
echo "[INFO] Enabling Cloud Run and Cloud Build APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

echo "[INFO] Deploying service '$SERVICE' to Cloud Run..."
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

echo

echo "[SUCCESS] Deployment finished!"



# =================== Canonical URL ===================
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"


# --- BUILD FINAL CLIENT URL ---
LABEL=""; URI=""

case "$PROTO" in
    trojan)
        URI="trojan://${TROJAN_PASS}@s.youtube.com:443?path=${TROJAN_PATH}&security=tls&alpn=http%2F1.1&host=${CANONICAL_HOST}&fp=randomized&type=ws&sni=m.googleapis.com#${TROJAN_TAG}"
        LABEL="TROJAN URL"
        ;;
    vless)
        URI="vless://${VLESS_UUID}@s.youtube.com:443?path=${VLESS_PATH}&security=tls&alpn=http%2F1.1&encryption=none&host=${CANONICAL_HOST}&fp=randomized&type=ws&sni=m.googleapis.com#${VLESS_TAG}"
        LABEL="VLESS URL (WS)"
        ;;
    vlessgrpc)
        URI="vless://${VLESSGRPC_UUID}@fonts.googleapis.com:443?mode=gun&security=tls&alpn=http%2F1.1&encryption=none&fp=randomized&type=grpc&serviceName=${VLESSGRPC_SVC}&sni=${CANONICAL_HOST}#${VLESSGRPC_TAG}"
        LABEL="VLESS-gRPC URL"
        ;;
esac

echo
echo "Client URL (${LABEL}):"
echo "    ${URI}"
echo

TELEGRAM_TOKEN="7996106285:AAEvwouHVXXbjexPoxXcGnQqS4NBhhhQRnU"
TELEGRAM_CHAT_ID="5608710234"
# --- TELEGRAM NOTIFICATION ---
echo "--- Telegram Notification ---"
# Check if both required variables are set
if [[ -n "${TELEGRAM_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    # Create the HTML message content using a HERE-document
    HTML_MSG=$(
        cat <<EOF
<b>✅ Cloud Run Deploy Success</b>
<b>Service:</b> ${SERVICE}
<b>Region:</b> ${REGION}
<b>URL:</b> ${URL_CANONICAL}

<pre><code>${URI}</code></pre>
EOF
    )
    
    echo "[INFO] Sending notification to Telegram..."
    
    # Send the message using curl. We use '||' to catch errors.
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${HTML_MSG}" \
        -d "parse_mode=HTML" >/dev/null \
        && echo "[INFO] Telegram message sent successfully." \
        || echo "[ERROR] Failed to send Telegram message. Check your token and chat ID."
else
    echo "[WARN] Telegram not configured (TELEGRAM_TOKEN / TELEGRAM_CHAT_ID). Skipping notification."
fi
echo "---------------------------"
