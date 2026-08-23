#!/bin/bash
set -euxo pipefail

# ===== 앱 배포 (Application.md: /opt/app, Python 3.12, Flask+Gunicorn) =====
dnf -y install python3.12

mkdir -p /opt/app
cat > /opt/app/app.py <<'PYEOF'
${app_py}
PYEOF
cat > /opt/app/requirements.txt <<'REQEOF'
${requirements}
REQEOF

python3.12 -m venv /opt/app/venv
/opt/app/venv/bin/pip install --no-cache-dir -r /opt/app/requirements.txt

# ===== systemd 유닛 (mark 2-7: 유닛 이름 정확히 'app', active + enabled) =====
# 환경변수는 [Service] 레벨로 지정 — app.py 가 import 시점에 env 없으면 raise 한다
cat > /etc/systemd/system/app.service <<UNITEOF
[Unit]
Description=wsc2026 order producer
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/app
Environment=STREAM_NAME=${stream_name}
Environment=AWS_REGION=${region}
ExecStart=/opt/app/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:${app_port} app:app
Restart=always

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now app
