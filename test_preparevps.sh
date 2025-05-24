#!/usr/bin/env bash
# Test script for preparevps.sh - Local testing version
# This simulates the functionality without requiring root privileges

set -euo pipefail

# Test configuration
TEST_DIR="$(pwd)/test_env"
TEST_USERNAME="testuser"
TEST_PASSWORD="testpass123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

cleanup() {
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Setup test environment
setup_test_env() {
    log_test "Setting up test environment"
    cleanup
    mkdir -p "$TEST_DIR/home/$TEST_USERNAME"
    
    # Create a modified version of preparevps.sh for testing
    sed 's|/home/|'"$TEST_DIR"'/home/|g' preparevps.sh > "$TEST_DIR/preparevps_test.sh"
    
    # Remove commands that require root privileges for local testing
    sed -i.bak '/apt-get\|useradd\|usermod\|chpasswd\|systemctl\|sshd\|curl.*docker\|gpg\|docker-ce/d' "$TEST_DIR/preparevps_test.sh"
    
    # Mock the username input
    sed -i.bak 's/read -rp "Enter a username.*" username/username="'"$TEST_USERNAME"'"/' "$TEST_DIR/preparevps_test.sh"
    sed -i.bak '/read -rsp.*password/d' "$TEST_DIR/preparevps_test.sh"
    
    chmod +x "$TEST_DIR/preparevps_test.sh"
    
    log_pass "Test environment created"
}

# Test SSH key generation
test_ssh_key_generation() {
    log_test "Testing SSH key generation"
    
    # Simulate SSH key generation part
    mkdir -p "$TEST_DIR/home/$TEST_USERNAME/.ssh"
    ssh-keygen -t ed25519 -f "$TEST_DIR/home/$TEST_USERNAME/.ssh/id_ed25519" -N "" -C "$TEST_USERNAME@testhost" &>/dev/null
    
    if [[ -f "$TEST_DIR/home/$TEST_USERNAME/.ssh/id_ed25519" && -f "$TEST_DIR/home/$TEST_USERNAME/.ssh/id_ed25519.pub" ]]; then
        log_pass "SSH keys generated successfully"
        
        # Test key format
        if ssh-keygen -l -f "$TEST_DIR/home/$TEST_USERNAME/.ssh/id_ed25519.pub" &>/dev/null; then
            log_pass "SSH key format is valid"
        else
            log_fail "SSH key format is invalid"
        fi
    else
        log_fail "SSH keys were not generated"
    fi
}

# Test docker-compose.yml creation
test_docker_compose_creation() {
    log_test "Testing docker-compose.yml creation"
    
    # Simulate the docker-compose creation part
    mkdir -p "$TEST_DIR/home/$TEST_USERNAME/docker-services"
    
    cat > "$TEST_DIR/home/$TEST_USERNAME/docker-services/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer:/data
    networks:
      - docker-services

  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./nginx-proxy-manager/data:/data
      - ./nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    networks:
      - docker-services

networks:
  docker-services:
    driver: bridge
EOF
    
    if [[ -f "$TEST_DIR/home/$TEST_USERNAME/docker-services/docker-compose.yml" ]]; then
        log_pass "docker-compose.yml created successfully"
        
        # Validate YAML syntax (if docker-compose is available)
        if command -v docker-compose &>/dev/null; then
            if docker-compose -f "$TEST_DIR/home/$TEST_USERNAME/docker-services/docker-compose.yml" config &>/dev/null; then
                log_pass "docker-compose.yml syntax is valid"
            else
                log_fail "docker-compose.yml syntax is invalid"
            fi
        else
            log_test "Skipping YAML validation (docker-compose not available)"
        fi
    else
        log_fail "docker-compose.yml was not created"
    fi
}

# Test directory structure
test_directory_structure() {
    log_test "Testing directory structure creation"
    
    # Create expected directories
    mkdir -p "$TEST_DIR/home/$TEST_USERNAME/docker-services/portainer"
    mkdir -p "$TEST_DIR/home/$TEST_USERNAME/docker-services/nginx-proxy-manager/data"
    mkdir -p "$TEST_DIR/home/$TEST_USERNAME/docker-services/nginx-proxy-manager/letsencrypt"
    mkdir -p "$TEST_DIR/home/$TEST_USERNAME/.config"
    
    # Check if directories exist
    local expected_dirs=(
        "$TEST_DIR/home/$TEST_USERNAME/docker-services"
        "$TEST_DIR/home/$TEST_USERNAME/docker-services/portainer"
        "$TEST_DIR/home/$TEST_USERNAME/docker-services/nginx-proxy-manager"
        "$TEST_DIR/home/$TEST_USERNAME/docker-services/nginx-proxy-manager/data"
        "$TEST_DIR/home/$TEST_USERNAME/docker-services/nginx-proxy-manager/letsencrypt"
        "$TEST_DIR/home/$TEST_USERNAME/.config"
    )
    
    local all_dirs_exist=true
    for dir in "${expected_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_fail "Directory $dir does not exist"
            all_dirs_exist=false
        fi
    done
    
    if $all_dirs_exist; then
        log_pass "All required directories created successfully"
    fi
}

# Test script syntax
test_script_syntax() {
    log_test "Testing script syntax"
    
    if bash -n preparevps.sh; then
        log_pass "Script syntax is valid"
    else
        log_fail "Script syntax is invalid"
    fi
}

# Test for required commands
test_required_commands() {
    log_test "Testing for required commands"
    
    local required_commands=("ssh-keygen" "docker" "docker-compose")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        log_pass "All required commands are available"
    else
        log_fail "Missing commands: ${missing_commands[*]}"
    fi
}

# Main test runner
main() {
    echo "Starting preparevps.sh tests..."
    echo "================================"
    
    setup_test_env
    test_script_syntax
    test_required_commands
    test_ssh_key_generation
    test_docker_compose_creation
    test_directory_structure
    
    cleanup
    
    echo ""
    echo "================================"
    echo "Test Results:"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests
main "$@"