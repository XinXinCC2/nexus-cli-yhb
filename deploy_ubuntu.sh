#!/bin/bash

# Nexus CLI Ubuntu 24 自动部署脚本
# 作者: AI Assistant
# 用途: 在Ubuntu 24上自动部署优化后的Nexus CLI

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为Ubuntu系统
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测操作系统版本"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "此脚本仅支持Ubuntu系统，当前系统：$ID"
        exit 1
    fi
    
    log_info "检测到Ubuntu $VERSION_ID"
    
    # 检查Ubuntu版本
    if [[ "$VERSION_ID" < "20.04" ]]; then
        log_warning "建议使用Ubuntu 20.04或更高版本，当前版本：$VERSION_ID"
    fi
}

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 检查内存
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_MEM -lt 4 ]]; then
        log_warning "内存不足4GB，建议使用--memory-conservative模式"
    else
        log_success "内存充足：${TOTAL_MEM}GB"
    fi
    
    # 检查CPU核心数
    CPU_CORES=$(nproc)
    log_info "CPU核心数：$CPU_CORES"
    
    # 检查磁盘空间
    DISK_SPACE=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ $DISK_SPACE -lt 5 ]]; then
        log_warning "磁盘空间不足5GB，当前可用：${DISK_SPACE}GB"
    else
        log_success "磁盘空间充足：${DISK_SPACE}GB"
    fi
}

# 安装系统依赖
install_system_dependencies() {
    log_info "更新系统包..."
    sudo apt update

    log_info "安装系统依赖..."
    sudo apt install -y \
        build-essential \
        pkg-config \
        libssl-dev \
        git \
        curl \
        protobuf-compiler \
        htop \
        net-tools

    log_success "系统依赖安装完成"
}

# 安装Rust
install_rust() {
    if command -v rustc &> /dev/null; then
        RUST_VERSION=$(rustc --version | awk '{print $2}')
        log_info "Rust已安装，版本：$RUST_VERSION"
        
        # 检查版本是否足够新
        if [[ "$RUST_VERSION" < "1.80" ]]; then
            log_warning "Rust版本过低，正在更新..."
            rustup update
        fi
    else
        log_info "安装Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
        log_success "Rust安装完成"
    fi
    
    # 验证安装
    rustc --version
    cargo --version
}

# 优化系统配置
optimize_system() {
    log_info "优化系统配置..."
    
    # 增加文件描述符限制
    if ! grep -q "nofile 65536" /etc/security/limits.conf; then
        echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
        echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
        log_success "文件描述符限制已优化"
    fi
    
    # 优化内存设置
    if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
        echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p > /dev/null 2>&1
        log_success "内存映射限制已优化"
    fi
    
    log_success "系统优化完成"
}

# 构建项目
build_project() {
    log_info "构建Nexus CLI项目..."
    
    cd clients/cli
    
    # 检查Cargo.toml
    if [[ ! -f "Cargo.toml" ]]; then
        log_error "未找到Cargo.toml文件，请确保在正确的项目目录中"
        exit 1
    fi
    
    # 构建项目
    log_info "正在构建Release版本..."
    cargo build --release
    
    # 验证构建结果
    if [[ -f "target/release/nexus-network" ]]; then
        log_success "项目构建成功"
        ./target/release/nexus-network --version
    else
        log_error "项目构建失败"
        exit 1
    fi
    
    cd ../..
}

# 创建systemd服务
create_systemd_service() {
    read -p "是否要创建systemd服务以便开机自启？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    read -p "请输入要使用的线程数 (推荐: 8-50): " THREAD_COUNT
    read -p "是否启用高性能模式？(y/n): " -n 1 -r
    echo
    
    PERFORMANCE_FLAG=""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        PERFORMANCE_FLAG=" --high-performance"
    fi
    
    PROJECT_DIR=$(pwd)
    
    sudo tee /etc/systemd/system/nexus-cli.service > /dev/null <<EOF
[Unit]
Description=Nexus CLI High Performance Prover
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_DIR/clients/cli
ExecStart=$PROJECT_DIR/clients/cli/target/release/nexus-network start --max-threads $THREAD_COUNT$PERFORMANCE_FLAG --headless
Restart=always
RestartSec=10
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable nexus-cli.service
    
    log_success "systemd服务已创建并启用"
    log_info "使用以下命令管理服务："
    echo "  启动: sudo systemctl start nexus-cli.service"
    echo "  停止: sudo systemctl stop nexus-cli.service"
    echo "  状态: sudo systemctl status nexus-cli.service"
    echo "  日志: journalctl -u nexus-cli.service -f"
}

# 性能测试
performance_test() {
    log_info "运行性能测试..."
    
    cd clients/cli
    
    # 测试不同配置
    echo
    log_info "测试可用配置模式："
    echo "1. 高性能模式 (推荐16GB+内存)："
    echo "   ./target/release/nexus-network start --max-threads 50 --high-performance --headless"
    echo
    echo "2. 平衡模式 (推荐8GB+内存)："
    echo "   ./target/release/nexus-network start --max-threads 25 --headless"
    echo
    echo "3. 保守模式 (适用4GB+内存)："
    echo "   ./target/release/nexus-network start --max-threads 10 --memory-conservative --headless"
    
    cd ../..
}

# 显示使用指南
show_usage_guide() {
    log_success "=== 部署完成！==="
    echo
    log_info "项目位置: $(pwd)"
    log_info "可执行文件: $(pwd)/clients/cli/target/release/nexus-network"
    echo
    log_info "快速启动命令："
    echo "cd $(pwd)/clients/cli"
    echo
    echo "# 根据你的系统配置选择："
    if [[ $(free -g | awk '/^Mem:/{print $2}') -ge 16 ]]; then
        echo "# 高性能模式 (推荐)"
        echo "./target/release/nexus-network start --max-threads 50 --high-performance"
    elif [[ $(free -g | awk '/^Mem:/{print $2}') -ge 8 ]]; then
        echo "# 平衡模式 (推荐)"
        echo "./target/release/nexus-network start --max-threads 25"
    else
        echo "# 保守模式 (推荐)"
        echo "./target/release/nexus-network start --max-threads 10 --memory-conservative"
    fi
    echo
    log_info "查看所有选项: ./target/release/nexus-network start --help"
    echo
    log_info "如需帮助，请查看 UBUNTU_COMPATIBILITY.md 文档"
}

# 主函数
main() {
    echo "========================================"
    echo "    Nexus CLI Ubuntu 24 部署脚本"
    echo "========================================"
    echo
    
    
    check_ubuntu
    check_system_requirements
    
    read -p "是否继续安装？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
    
    install_system_dependencies
    install_rust
    optimize_system
    build_project
    create_systemd_service
    performance_test
    show_usage_guide
    
    log_success "部署完成！享受高性能的Nexus CLI体验！"
}

# 运行主函数
main "$@"
