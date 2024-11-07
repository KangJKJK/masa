#!/bin/bash

# 출력용 색상
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 색상 없음

# 성공 메시지 출력 함수
print_success() {
    echo -e "${GREEN}$1${NC}"
}

# 필수 패키지 설치
echo -e "${CYAN}필수 패키지 설치 중...${NC}"
sudo apt-get update
sudo apt-get install -y \
    git \
    curl

# UFW 설치 (설치되어 있지 않은 경우)
if ! command -v ufw &> /dev/null; then
    echo -e "${YELLOW}UFW가 설치되어 있지 않습니다. 설치 중...${NC}"
    sudo apt install -y ufw
    print_success "UFW 설치 완료"
else
    echo -e "${BLUE}UFW가 이미 설치되어 있습니다.${NC}"
fi

# Docker 및 Docker Compose 설치 확인
if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker 또는 Docker Compose가 설치되어 있지 않습니다. 설치를 진행합니다...${NC}"
    sudo apt update && sudo apt install -y docker.io docker-compose
else
    echo -e "${GREEN}Docker 및 Docker Compose가 이미 설치되어 있습니다.${NC}"
fi

# Docker 서비스 시작
sudo systemctl start docker
sudo systemctl enable docker

# 현재 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER
print_success "필수 패키지 설치 완료"

# 명령어 존재 여부 확인 함수
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}오류: $1이(가) 설치되지 않았습니다${NC}"
        exit 1
    fi
}

# 사전 요구사항 확인
echo -e "${MAGENTA}Ubuntu 시스템 확인 중...${NC}"
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${RED}오류: 이 스크립트는 Ubuntu 시스템에서만 실행할 수 있습니다${NC}"
    exit 1
fi

# 프로젝트 디렉토리 생성 및 이동
PROJECT_DIR="masa-oracle"

# 저장소 복제
echo -e "${CYAN}Masa Oracle 저장소 복제 중...${NC}"
git clone https://github.com/masa-finance/masa-oracle.git
cd $PROJECT_DIR

# .env 파일 생성 전에 사용 가능한 포트 찾기
echo -e "${YELLOW}사용 가능한 포트 확인 중...${NC}"
PORT=8080
while nc -z localhost $PORT 2>/dev/null; do
    echo -e "${MAGENTA}포트 $PORT는 이미 사용 중입니다. 다음 포트 확인...${NC}"
    PORT=$((PORT + 1))
done
echo -e "${GREEN}사용 가능한 포트 찾음: $PORT${NC}"

# .env 파일 생성 전 중요 고지사항 표시
echo -e "\n${MAGENTA}=== 중요 안내사항 ===${NC}"
echo -e "${YELLOW}Masa 노드 참여를 위한 필수 요구사항:${NC}"
echo -e "1. 모든 노드는 스테이킹이 필요합니다 (최소 1000 Sepolia MASA)"
echo -e "2. Sepolia ETH가 필요합니다 (퍼블릭 faucet에서 획득 가능)"
echo -e "3. Sepolia MASA 토큰이 필요합니다 ('make faucet' 명령어로 1000 MASA 획득 가능)\n"

echo -e "${YELLOW}워커(데이터 제공자)로 참여하기 위한 추가 요구사항:${NC}"
echo -e "1. Twitter 워커: 유료 Twitter 계정 필요"
echo -e "2. Discord 워커: Discord 봇 토큰 필요"
echo -e "3. Telegram 워커: Telegram API 자격 증명 및 봇 설정 필요\n"
echo -e "${YELLOW}가이드라인에 따르면 트위터워커가 중요하므로 트위터워커로 구동합니다.${NC}"

echo -e "${CYAN}계속 진행하시겠습니까? (y/n)${NC}"
read -p "" confirm
if [[ $confirm != [yY] ]]; then
    echo -e "${RED}설치가 취소되었습니다.${NC}"
    exit 1
fi

# .env 파일 생성
echo -e "${CYAN}.env 파일 생성 중...${NC}"
cat > .env << EOL
# 기본 노드 설정
BOOTNODES=/ip4/35.223.224.220/udp/4001/quic-v1/p2p/16Uiu2HAmPxXXjR1XJEwckh6q1UStheMmGaGe8fyXdeRs3SejadSa
RPC_URL=https://ethereum-sepolia.publicnode.com
ENV=test
FILE_PATH=.
PORT=$PORT

# Worker 설정
TWITTER_SCRAPER=true
DISCORD_SCRAPER=false
WEB_SCRAPER=false
TELEGRAM_SCRAPER=false

# Twitter 설정
TWITTER_ACCOUNTS=
TWITTER_PASSWORD=
USER_AGENTS="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36,Mozilla/5.0 (Macintosh; Intel Mac OS X 14.7; rv:131.0) Gecko/20100101 Firefox/131.0"

# Discord 설정
DISCORD_BOT_TOKEN=

# Telegram 설정
TELEGRAM_APP_ID=
TELEGRAM_APP_HASH=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHANNEL_USERNAME=
EOL
print_success ".env 파일 생성 완료"

# Docker 이미지 빌드
echo -e "${YELLOW}Docker 이미지 빌드 중...${NC}"
docker-compose build

# UFW 설정
echo -e "${BLUE}방화벽 설정 중...${NC}"
if command -v ufw &> /dev/null; then
    sudo ufw allow $PORT/tcp
    print_success "포트 $PORT가 방화벽에서 허용되었습니다"
else
    echo -e "${RED}UFW가 설치되어 있지 않습니다. 필요한 경우 수동으로 포트를 열어주세요${NC}"
fi

# 노드 시작
echo -e "${MAGENTA}Masa 노드 시작 중...${NC}"
docker-compose up -d

# 노드 시작 대기 및 공개키 확인
echo -e "${CYAN}노드 시작 대기 중...${NC}"
sleep 10
NODE_LOGS=$(docker-compose logs masa-node)
PUBLIC_KEY=$(echo "$NODE_LOGS" | grep "Public Key:" | awk '{print $3}')

print_success "노드가 성공적으로 시작되었습니다!"
echo -e "${GREEN}공개키: $PUBLIC_KEY${NC}"
echo -e "${GREEN}이제 각 단계들을 숙지하세요.${NC}"
echo -e "${YELLOW}노드의 공개키 주소로 Sepolia ETH 전송: $PUBLIC_KEY${NC}"
read -p "공개키 주소로 eth를 보내셨나요? (y/n)" :
docker-compose run --rm masa-node /usr/bin/masa-node --faucet
docker-compose run --rm masa-node /usr/bin/masa-node --stake 1000
docker-compose up -d
NODE_LOGS=$(docker-compose logs --tail 20 masa-node)  # 최신 20줄의 로그만 가져오기

echo -e "${GREEN}masa 노드 설치 및 설정이 완료되었습니다.${NC}"
echo -e "${YELLOW}로그는 다음명령어로 확인하세요: docker-compose logs -f masa-node${NC}"
echo -e "${YELLOW}이곳에서 리더보드를 확인하세요: https://deepnote.com/app/masa-analytics/Masa-Testnet-Leaderboard-4a301f2d-43f0-4b35-bb30-f992efc957e6${NC}"
echo -e "${GREEN}이곳에서 리더보드를 확인하세요: https://deepnote.com/app/masa-analytics/Masa-Testnet-Leaderboard-4a301f2d-43f0-4b35-bb30-f992efc957e6${NC}"
echo -e "${GREEN}스크립트작성자: https://t.me/kjkresearch${NC}"