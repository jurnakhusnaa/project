#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Skrip ini harus dijalankan sebagai root."
    exit 1
fi

install_services() {
    local REPO="https://raw.githubusercontent.com/jurnakhusnaa/project/master/files/"
    local LIMIT_IP_SERVICES=("limiter-vm" "limiter-vl" "limiter-trj" "limiter-shd" "limiter-ssh")
    local LIMIT_IP_REMOTE_FILES=("lite-vm" "lite-vl" "lite-trj" "lite-shd" "lite-ssh")
    local LIMIT_QUOTA_SERVICES=("limitvmess" "limitvless" "limittrojan" "limitshadowsocks")
    local LIMIT_QUOTA_REMOTE_FILES=("vmess" "vless" "trojan" "shadowsocks")
    local ALL_SERVICES=("${LIMIT_IP_SERVICES[@]}" "${LIMIT_QUOTA_SERVICES[@]}")

    echo "Memulai instalasi layanan systemd..."

    echo "1. Menghapus layanan lama dan file terkait..."
    for service in "${ALL_SERVICES[@]}"; do
        systemctl disable --now "${service}.timer" &>/dev/null
        systemctl disable --now "${service}.service" &>/dev/null
        rm -f "/etc/systemd/system/${service}.service"
        rm -f "/etc/systemd/system/${service}.timer"
        rm -rf "/etc/systemd/system/${service}.service.d"
        echo "- ${service} dihapus."
    done

    rm -f "/usr/local/bin/"{lite-vm,lite-vl,lite-trj,lite-shd,lite-ssh} &>/dev/null
    rm -f "/etc/xray/limit."{vmess,vless,trojan,shadowsocks} &>/dev/null
    echo "- File biner lama dihapus."

    echo "2. Menginstal skrip dan membuat layanan Limit IP..."
    for i in "${!LIMIT_IP_SERVICES[@]}"; do
        local service="${LIMIT_IP_SERVICES[$i]}"
        local remote_file="${LIMIT_IP_REMOTE_FILES[$i]}"
        local binary_path="/usr/local/bin/${remote_file}"

        echo "- Mengunduh skrip ${remote_file}..."
        wget -q -O "${binary_path}" "${REPO}/${remote_file}" || {
            echo "Gagal mengunduh ${remote_file}. Lanjut ke layanan berikutnya."
            continue
        }
        chmod +x "${binary_path}"

        cat > "/etc/systemd/system/${service}.service" << EOF
[Unit]
Description=${service} Service
After=network.target

[Service]
Type=oneshot
ExecStart=${binary_path}

[Install]
WantedBy=multi-user.target
EOF

        # Timer per 5 menit, offset sesuai index
        local offset=$((i % 5))
        cat > "/etc/systemd/system/${service}.timer" << EOF
[Unit]
Description=Run ${service} every 5 minutes

[Timer]
OnCalendar=*:$(($offset))/5
Persistent=true
Unit=${service}.service

[Install]
WantedBy=timers.target
EOF

        # Override untuk membatasi restart
        mkdir -p "/etc/systemd/system/${service}.service.d"
        cat > "/etc/systemd/system/${service}.service.d/override.conf" << EOF
[Service]
Restart=on-failure
RestartSec=10s
StartLimitBurst=3
StartLimitIntervalSec=60
EOF

        echo "- Layanan ${service} dibuat dan dioptimasi."
    done

    echo "3. Menginstal skrip dan membuat layanan Limit Kuota..."
    mkdir -p /etc/xray/
    for i in "${!LIMIT_QUOTA_SERVICES[@]}"; do
        local service="${LIMIT_QUOTA_SERVICES[$i]}"
        local remote_file="${LIMIT_QUOTA_REMOTE_FILES[$i]}"
        local binary_path="/etc/xray/limit.${remote_file}"

        echo "- Mengunduh skrip limit.${remote_file}..."
        wget -q -O "${binary_path}" "${REPO}/${remote_file}" || {
            echo "Gagal mengunduh ${remote_file}. Lanjut ke layanan berikutnya."
            continue
        }
        chmod +x "${binary_path}"

        cat > "/etc/systemd/system/${service}.service" << EOF
[Unit]
Description=${service} Service
After=network.target

[Service]
Type=oneshot
ExecStart=${binary_path}

[Install]
WantedBy=multi-user.target
EOF

        # Timer per 5 menit, offset berbeda dari IP services (misal +5)
        local offset=$((i + 5))
        cat > "/etc/systemd/system/${service}.timer" << EOF
[Unit]
Description=Run ${service} every 5 minutes

[Timer]
OnCalendar=*:$(($offset % 5))/5
Persistent=true
Unit=${service}.service

[Install]
WantedBy=timers.target
EOF

        # Override restart
        mkdir -p "/etc/systemd/system/${service}.service.d"
        cat > "/etc/systemd/system/${service}.service.d/override.conf" << EOF
[Service]
Restart=on-failure
RestartSec=10s
StartLimitBurst=3
StartLimitIntervalSec=60
EOF

        echo "- Layanan ${service} dibuat dan dioptimasi."
    done

    echo "4. Memuat ulang systemd & mengaktifkan semua timer..."
    systemctl daemon-reload
    for service in "${ALL_SERVICES[@]}"; do
        systemctl enable --now "${service}.timer" &>/dev/null
        echo "- ${service}.timer diaktifkan."
    done

    echo "Semua layanan berhasil dipasang dan dioptimasi."
}

install_services

rm -f "$0"
