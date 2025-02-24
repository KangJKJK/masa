#!/bin/bash

# 출력용 색상
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 색상 없음

clear
echo -e "${YELLOW}=== Masa 노드 설치 스크립트 ===${NC}"
echo -e "${YELLOW}이곳에서 리더보드를 확인하세요: https://deepnote.com/app/masa-analytics/Masa-Testnet-Extension-Leaderboard-033bcce9-1200-4fc1-b9af-83106d30bde1?utm_source=share-modal&utm_medium=product-shared-content&utm_campaign=data-app&utm_content=033bcce9-1200-4fc1-b9af-83106d30bde1${NC}"
echo -e "${GREEN}1. 최초 설치${NC}"
echo -e "${GREEN}2. 설치 후 싱크 과정${NC}"
read -p "원하는 작업을 선택하세요 (1 또는 2): " choice

case $choice in
    1)
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
            echo -e "${GREEN}UFW 설치 완료${NC}"
        else
            echo -e "${BLUE}UFW가 이미 설치되어 있습니다.${NC}"
        fi

        echo -e "${GREEN}필수 패키지 설치 완료${NC}"
        
        # 사전 요구사항 확인
        echo -e "${MAGENTA}Ubuntu 시스템 확인 중...${NC}"
        if ! grep -q "Ubuntu" /etc/os-release; then
            echo -e "${RED}오류: 이 스크립트는 Ubuntu 시스템에서만 실행할 수 있습니다${NC}"
            exit 1
        fi

        # 시스템 요구사항 확인
        echo -e "${MAGENTA}시스템 요구사항 확인 중...${NC}"
        CPU_CORES=$(nproc)
        TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
        STORAGE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

        if [ $CPU_CORES -lt 2 ] || [ $TOTAL_RAM -lt 4 ] || [ $STORAGE -lt 120 ]; then
            echo -e "${RED}시스템이 최소 요구사항을 충족하지 않습니다:${NC}"
            echo -e "필요: CPU 2코어 이상, RAM 4GB 이상, 저장공간 120GB 이상"
            echo -e "현재: CPU ${CPU_CORES}코어, RAM ${TOTAL_RAM}GB, 저장공간 ${STORAGE}GB"
            exit 1
        fi

        # 프로젝트 디렉토리 생성 및 이동
        PROJECT_DIR="masa-oracle"

        # 저장소 복제 및 최신 릴리즈 체크아웃
        echo -e "${CYAN}Masa Oracle 저장소 복제 중...${NC}"
        git clone https://github.com/masa-finance/masa-oracle.git
        cd $PROJECT_DIR

        echo -e "${CYAN}최신 릴리즈 태그 체크아웃 중...${NC}"
        latest_tag=$(git describe --tags `git rev-list --tags --max-count=1`)
        git checkout $latest_tag
        echo -e "${GREEN}최신 버전 ($latest_tag) 체크아웃 완료${NC}"

        # contracts 의존성 설치
        echo -e "${CYAN}contracts 의존성 설치 중...${NC}"
        cd contracts
        if command -v npm &> /dev/null; then
            npm install
        elif command -v yarn &> /dev/null; then
            yarn install
        else
            echo -e "${RED}npm 또는 yarn이 설치되어 있지 않습니다. Node.js를 설치해주세요.${NC}"
            exit 1
        fi
        cd ..
        echo -e "${GREEN}contracts 의존성 설치 완료${NC}"

        # .env 파일 생성 전에 사용 가능한 포트 찾기
        echo -e "${YELLOW}사용 가능한 포트 확인 중...${NC}"
        PORT=8080
        while nc -z localhost $PORT 2>/dev/null; do
            echo -e "${MAGENTA}포트 $PORT는 이미 사용 중입니다. 다음 포트 확인...${NC}"
            PORT=$((PORT + 1))
        done
        echo -e "${GREEN}사용 가능한 포트 찾음: $PORT${NC}"
        sudo ufw enable
        sudo ufw allow $PORT/tcp
        sudo ufw allow 22/tcp
        echo -e "${GREEN}포트 $PORT가 방화벽에서 허용되었습니다${NC}"

        # Twitter 계정 정보 안내 및 입력 받기
        echo -e "${YELLOW}Twitter 계정 정보 입력이 필요합니다${NC}"
        echo -e "${YELLOW}주의사항:${NC}"
        echo -e "1. Twitter 프리미엄 계정이 필요합니다"
        echo -e "2. 여러 계정을 사용할 수 있으며, 계정 입력 시 쉼표(,)로 구분해 주세요"
        echo -e "예시: username1,username2,username3"
        echo -e "예시: password1,password2,password3"
        echo

        read -p "Twitter 사용자명 (쉼표로 구분): " TWITTER_USERNAMES
        read -sp "Twitter 비밀번호 (쉼표로 구분): " TWITTER_PASSWORDS
        echo # 새 줄 추가

        # 쉼표로 구분된 사용자명과 비밀번호를 결합하여 TWITTER_ACCOUNTS 형식으로 변환
        IFS=',' read -ra USERNAMES <<< "$TWITTER_USERNAMES"
        IFS=',' read -ra PASSWORDS <<< "$TWITTER_PASSWORDS"
        TWITTER_ACCOUNTS=""
        for i in "${!USERNAMES[@]}"; do
            if [ $i -gt 0 ]; then
                TWITTER_ACCOUNTS+=","
            fi
            TWITTER_ACCOUNTS+="${USERNAMES[$i]}:${PASSWORDS[$i]}"
        done

        # .env 파일 생성
        echo -e "${CYAN}.env 파일 생성 중...${NC}"
cat > .env << EOL
# Base .env configuration
RPC_URL=https://ethereum-sepolia.publicnode.com
ENV=local
FILE_PATH=.
VALIDATOR=false
PORT=$PORT
API_ENABLED=true  # Set to true to allow API calls, false to disable them
TWITTER_SCRAPER=true
TWITTER_ACCOUNTS=${TWITTER_ACCOUNTS}
EOL
        echo -e "${GREEN}.env 파일 생성 완료${NC}"

        # 노드실행
        sudo apt-get install -y golang-1.22
        export PATH="/usr/local/opt/go@1.22/bin:$PATH"
        source ~/.bash_profile
        go version
        make build
        
        echo -e "${YELLOW}멀티어드레스와 퍼블릭키가 표시될겁니다.${NC}"
        echo -e "${YELLOW}멀티어드레스는 'Multiaddress:' 다음에 나오는 긴 문자열 중 마지막 부분입니다.${NC}"
        echo -e "${YELLOW}예: /ip4/192.168.1.8/udp/4001/quic-v1/p2p/16Uiu2HAm... 에서${NC}"
        echo -e "${YELLOW}16Uiu2HAm... 부분이 실제 멀티어드레스입니다.${NC}"
        make run

        ;;
    2)
        echo -e "${YELLOW}=== 설치 후 싱크 과정을 시작합니다 ===${NC}"
        
        # 프로젝트 디렉토리로 이동
        cd masa-oracle
        
        # Go 환경변수 설정
        export PATH="/usr/local/opt/go@1.22/bin:$PATH"
        source ~/.bash_profile
        
        # .env 파일 수정
        echo -e "${CYAN}.env 파일 수정 중...${NC}"
        sed -i 's/VALIDATOR=false/VALIDATOR=true/' .env
        
        read -p "멀티어드레스를 입력하세요: " MULTIADDR
        read -p "퍼블릭키를 입력하세요: " PUBLIC_KEY

        # .env 파일 업데이트
        sed -i "s/^PUBLIC_KEY=.*/PUBLIC_KEY=$PUBLIC_KEY/" .env
        sed -i "s/^MULTIADDR=.*/MULTIADDR=$MULTIADDR/" .env

        # 빌드 실행
        echo -e "${CYAN}노드 빌드 중...${NC}"
        make build

        # Faucet 및 Stake 실행
        echo -e "${CYAN}Faucet 요청 중...${NC}"
        make faucet
        echo -e "${CYAN}Stake 진행 중...${NC}"
        make stake

        # Bootnode 정보 추가
        echo -e "${CYAN}Bootnode 정보 추가 중...${NC}"
        echo 'BOOTNODES="/dns4/boot-1.test.miners.masa.ai/udp/4001/quic-v1/p2p/16Uiu2HAm9Nkz9kEMnL1YqPTtXZHQZ1E9rhquwSqKNsUViqTojLZt,/dns4/boot-2.test.miners.masa.ai/udp/4001/quic-v1/p2p/16Uiu2HAm7KfNcv3QBPRjANctYjcDnUvcog26QeJnhDN9nazHz9Wi,/dns4/boot-3.test.miners.masa.ai/udp/4001/quic-v1/p2p/16Uiu2HAmBcNRvvXMxyj45fCMAmTKD4bkXu92Wtv4hpzRiTQNLTsL"' >> .env
        
        echo -e "${CYAN}노드를 실행합니다...${NC}"
        make run
        
        echo -e "${GREEN}싱크 과정이 시작되었습니다.${NC}"
        echo -e "${YELLOW}노드가 정상적으로 동작하는지 로그를 확인해주세요.${NC}"
        ;;
    *)
        echo -e "${RED}잘못된 선택입니다. 1 또는 2를 선택해주세요.${NC}"
        exit 1
        ;;
esac
