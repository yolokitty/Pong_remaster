`timescale 1ns / 1ps

// ==========================================
// [모듈 선언] module은 하나의 거대한 칩(Chip)의 껍데기를 만드는 것과 같습니다.
// 괄호() 안에는 이 칩 바깥으로 뻗어나가는 물리적인 다리(Pin)들의 이름을 적어줍니다.
// ==========================================
module pong_top(
    // --- [입력 포트] 보드 바깥의 스위치/버튼에서 FPGA 안으로 들어오는 전기 신호들 ---
    input clk,          // Basys3 보드의 '심장'입니다. 내장된 수정 발진기에서 1초에 1억 번(100MHz) 진동하는 전기 펄스가 들어옵니다.
    input rst_p,        // 게임을 초기화하는 리셋 버튼.
    input sw_start,     // 게임 시작/일시정지 스위치. (1로 올리면 게임 진행, 0으로 내리면 시간 정지)
    input sw_test,      // 모니터 화면이 안 잡힐 때, 강제로 전체 화면을 하얗게 켜서 모니터 자동 조정을 돕는 스위치.
    input sw_score_limit,// 끄면 3선승제, 켜면 10선승제로 변경
    
    input sw_ai_en,
    input predict_mode, // 싱글 모드(AI 모드)
    
    input btn_p1_up,    // 플레이어 1(왼쪽) 패들을 위로 올리는 버튼
    input btn_p1_down,  // 플레이어 1(왼쪽) 패들을 아래로 내리는 버튼
    input btn_p1_dash,  // 플레이어 1 대시 버튼 (누르고 있으면 2배 빨리 움직임. PMOD 확장 핀에 연결됨)
    
    input btn_p2_up,    // 플레이어 2(오른쪽) 패들을 위로 올리는 버튼
    input btn_p2_down,  // 플레이어 2(오른쪽) 패들을 아래로 내리는 버튼
    input btn_p2_dash,  // 플레이어 2 대시 버튼 (PMOD 확장 핀에 연결됨)
    
    // --- [출력 포트] FPGA 내부에서 계산된 결과를 모니터 케이블이나 스피커로 쏴주는 신호들 ---
    output [3:0] vga_r, // VGA 케이블의 1, 2, 3번 핀으로 나가는 빨간색 아날로그 전압 신호 (4비트 = 0~15단계 밝기 조절)
    output [3:0] vga_g, // 초록색 출력
    output [3:0] vga_b, // 파란색 출력
    output hsync,       // 모니터 안의 전자빔에게 "가로줄 끝났으니 다음 줄로 넘어가!"라고 명령하는 가로 동기화 신호
    output vsync,       // 모니터 안의 전자빔에게 "화면 맨 아래까지 다 그렸으니 다시 맨 위로 올라가!"라고 명령하는 세로 동기화 신호
    output speaker_pin  // 스피커를 떨리게 만들 소리 파형(PWM 구형파) 출력 핀
);

    // ==========================================
    // [튜닝 파라미터] 기획자의 영역입니다.
    // parameter는 코드가 물리적인 회로로 굳어지기 전에 숫자를 결정하는 '상수'입니다.
    // 이 숫자들만 바꿔서 컴파일하면 게임의 난이도와 속도감을 완전히 바꿀 수 있습니다.
    // ==========================================
    parameter PADDLE_BASE_SPD = 4;   // 패들이 버튼을 누를 때 1프레임당 이동하는 픽셀 수 (기본 속도)
    parameter PADDLE_DASH_SPD = 10;  // 대시 버튼을 함께 누를 때 이동하는 픽셀 수 (빠른 속도)
    parameter BALL_INIT_DX    = 3;   // 공이 처음 출발할 때의 가로 방향(X축) 스피드
    parameter BALL_INIT_DY    = 2;   // 공이 처음 출발할 때의 세로 방향(Y축) 스피드
    parameter BALL_MAX_DX     = 12;  // 게임이 아무리 길어져도 공이 이 속도 이상으로는 빨라지지 않게 막는 한계치
    parameter ACCEL_HITS      = 2;   // 공이 패들에 이 횟수만큼 맞을 때마다 속도(DX)가 1씩 증가합니다.
    parameter WIN_SCORE_SHORT = 3;   // 짧은게임 선택시 판수
    parameter WIN_SCORE_LONG  = 10;  // 긴게임 선택시 판수

    // ==========================================
    // [절대 상수] 객체들의 크기와 위치 (수정 금지)
    // localparam은 모듈 내부에서만 쓰이는 상수로, 코딩 중 실수를 막아줍니다.
    // 렌더링(그림 그리기) 좌표와 히트박스(충돌 판정) 좌표를 완벽히 통일하기 위해 사용합니다.
    // ==========================================
    localparam P1_X = 30;  // 왼쪽 패들이 서 있는 X좌표 (화면 왼쪽에서 30픽셀 떨어짐)
    localparam P2_X = 760; // 오른쪽 패들이 서 있는 X좌표 (800 해상도의 오른쪽 끝자락)
    localparam P_W  = 10;  // 패들의 두께 (가로 10픽셀)
    localparam P_H  = 60;  // 패들의 길이 (세로 60픽셀)
    localparam B_S  = 10;  // 공의 크기 (10x10 정사각형. B_S는 Ball Size의 약자)

    // ==========================================
    // 1. 픽셀 클럭 분주기 (100MHz 심장을 33.3MHz로 늦추기)
    // 모니터 해상도 800x480 화면을 1초에 60번(60Hz) 정확히 그리려면,
    // 픽셀 하나를 그리는 붓의 속도(픽셀 클럭)가 정확히 33.3MHz여야 합니다.
    // ==========================================
    reg [1:0] clk_div = 0; // 0, 1, 2, 3까지 담을 수 있는 2비트짜리 작은 메모리 통(카운터)
    
    // always @(posedge clk)는 100MHz 심장이 '쿵' 하고 뛸 때(0->1 상승 엣지)마다 실행됩니다.
    always @(posedge clk) begin
        if (clk_div == 2) clk_div <= 0; // 값이 2가 되면 다시 0으로 비웁니다. 즉 0->1->2->0->1->2 무한 반복!
        else clk_div <= clk_div + 1;    // 2가 아니면 1씩 더합니다.
    end
    
    // 카운터가 0일 때만 참(1)이 되는 신호선(wire). 100MHz 중에 1/3만 켜지므로 33.3MHz가 됩니다.
    wire clk_33M_unbuf = (clk_div == 0); 
    
    // BUFG (Global Clock Buffer): 방금 만든 33.3MHz 신호는 너무 약해서 칩 전체를 움직일 수 없습니다.
    // 이 신호를 칩 내부의 고속도로(글로벌 클럭망)에 태워서 강력하게 증폭해 주는 특수 부품입니다.
    wire clk_33M; // 최종적으로 우리가 사용할 튼튼한 33.3MHz 클럭 선
    BUFG bufg_inst (.I(clk_33M_unbuf), .O(clk_33M));

    // ==========================================
    // 2. 800x480 VGA 타이밍 컨트롤러 (모니터와 대화하는 규격)
    // 모니터 안의 눈에 보이지 않는 전자빔이 좌측 상단부터 우측 하단까지 
    // 지그재그로 스캔하며 그림을 그리는 과정을 하드웨어 카운터로 시뮬레이션 합니다.
    // ==========================================
    // 산업 표준 WVGA(800x480) 60Hz 타이밍 스펙. 
    // 눈에 보이는 Active 영역에 여백(Front/Back Porch)과 빔이 돌아오는 시간(Sync)을 더합니다.
    localparam H_ACTIVE = 800, H_FP = 40, H_SYNC = 128, H_BP = 88; // 다 더하면 가로 한 줄에 총 1056 클럭 소요
    localparam V_ACTIVE = 480, V_FP = 10, V_SYNC =  2, V_BP = 33;  // 다 더하면 세로로 총 525 줄 소요

    reg [10:0] h_cnt = 0; // 가로 픽셀 위치를 추적하는 카운터 (0 ~ 1055)
    reg [9:0]  v_cnt = 0; // 세로 줄 위치를 추적하는 카운터 (0 ~ 524)
    
    always @(posedge clk_33M) begin // 33.3MHz 붓질 한 번마다 실행
        if (h_cnt == (H_ACTIVE + H_FP + H_SYNC + H_BP - 1)) begin // 가로줄 맨 끝에 도달하면
            h_cnt <= 0; // 가로 위치를 0(맨 왼쪽)으로 되돌리고,
            // 세로줄도 맨 아래 끝에 도달했으면 맨 위(0)로, 아니면 세로로 한 줄 아래(+1)로 내립니다.
            v_cnt <= (v_cnt == (V_ACTIVE + V_FP + V_SYNC + V_BP - 1)) ? 0 : v_cnt + 1;
        end else begin
            h_cnt <= h_cnt + 1; // 아직 가로줄 끝이 아니면 오른쪽으로 1픽셀 계속 이동
        end
    end

    // 동기화 신호(Sync): 모니터가 줄바꿈을 언제 해야 할지 알려주는 전기 신호.
    // 정해진 SYNC 구간(시간)에만 0(Low) 전압을 줍니다. (~는 비트를 반대로 뒤집는 Not 연산자)
    assign hsync = ~(h_cnt >= (H_ACTIVE + H_FP) && h_cnt < (H_ACTIVE + H_FP + H_SYNC));
    assign vsync = ~(v_cnt >= (V_ACTIVE + V_FP) && v_cnt < (V_ACTIVE + V_FP + V_SYNC));
    
    // 비디오 활성 신호: 현재 전자빔이 '눈에 보이는 모니터 영역(800x480)' 안에 있을 때만 1이 됩니다.
    wire video_on = (h_cnt < H_ACTIVE && v_cnt < V_ACTIVE); 
    
    // [매우 중요] 프레임 틱(Frame Tick)
    // 클럭(clk_33M) 단위로 게임을 계산하면 1초에 3천만 번 움직여서 공이 보이지도 않게 됩니다.
    // 화면을 맨 위부터 아래 끝까지 딱 한 번 다 그렸을 때(v_cnt == 481), 
    // 즉 1초에 딱 60번만 이 신호가 1클럭 동안 켜집니다. 이것이 게임 엔진의 '시간 단위'가 됩니다.
    wire frame_tick = (h_cnt == 0 && v_cnt == (V_ACTIVE + 1)); 

    // ==========================================
    // 3. 게임 메모리 (데이터 레지스터 선언)
    // ==========================================
    localparam S_PLAY = 1'b0, S_OVER = 1'b1; // 게임이 진행 중(0)인지 끝났는지(1) 나타내는 상태 상수
    reg state = S_PLAY; // 현재 게임 상태를 담는 메모리

    // [초보자 가이드] signed 키워드는 이 변수가 마이너스(-) 음수 값을 가질 수 있다는 뜻입니다!
    // 모니터 밖으로 공이 뚫고 나갔을 때 좌표가 마이너스가 되어야 정상적으로 버그 없이 득점 처리가 됩니다.
    reg signed [11:0] p1_y = 210, p2_y = 210; // 양쪽 패들의 수직(Y) 위치. (초기값 210은 대략 화면 중앙)
    reg [3:0] p1_score = 0, p2_score = 0;     // 양쪽 플레이어의 점수 (4비트 = 0~15점 표현 가능)

    // 공의 X, Y 좌표와 이동 방향(속도) 벡터
    reg signed [11:0] ball_x = 395, ball_y = 235; 
    reg signed [4:0] b1_dx = BALL_INIT_DX, b1_dy = BALL_INIT_DY;

    // 가속 시스템을 위한 메모리
    reg [4:0] b1_hit = 0; // 패들에 맞은 횟수를 기억하는 카운터
    reg signed [4:0] cur_dx1 = BALL_INIT_DX; // 공이 가속될 때마다 변하는 현재 수평 스피드

    // 사운드 발생을 지시하는 1클럭짜리 방아쇠(Trigger) 신호
    reg hit_wall = 0, hit_paddle = 0, hit_score = 0;
    

    // ==========================================
    // [ADD] 싱글모드 AI 제어 신호
    // ==========================================
    wire predict_up;
    wire predict_down;
    wire p2_up_ctrl;
    wire p2_down_ctrl;


    // [사운드 모듈 연결] 
    // 따로 만든 pong_sound.v 파일을 이 메인 칩 안에 부품처럼 끼워 넣고, 전선(wire)들을 연결해 줍니다.
    pong_sound sound_gen(
        .clk_33M(clk_33M),       // 심장 박동 연결
        .frame_tick(frame_tick), // 프레임 타이머 연결
        .v_cnt(v_cnt),           // ★ 오리지널 퐁 기술: 모니터 Y좌표 카운터를 소리 파형으로 직접 넘겨줌
        .hit_wall(hit_wall), .hit_paddle(hit_paddle), .hit_score(hit_score), // 방아쇠 신호 연결
        .audio_out(speaker_pin)  // 스피커로 나가는 최종 구형파 출력 연결
    );

    // 게임이 몇 판 내기인지 결정하는 멀티플렉서
    wire [3:0] win_score = sw_score_limit ? WIN_SCORE_SHORT : WIN_SCORE_LONG;

    // 🌟 [독립 득점 조건 전선] - Two ball 로직 완벽 제거
    wire p1_scored = (ball_x >= 790);
    wire p2_scored = (ball_x <= 0);

    // ==========================================
    // 4. [오리지널 퐁 복원] 진정한 하드웨어 난수 생성기
    // 난수(Random) 생성 칩 없이, 모니터를 그리고 있는 매우 빠른 카운터를 이용해 난수를 만듭니다.
    // 33.3MHz (1초에 3300만 번) 속도로 0부터 화면 맨 아래(469)까지 무한히 돕니다.
    // 누군가 득점하는 바로 그 순간의 찰나의 카운터 값을 낚아채서 공의 스폰 높이로 씁니다!
    // ==========================================
    reg [8:0] rand_y = 0;      // 0 ~ 469 (화면 안쪽) 범위에서 무한히 회전하는 카운터
    reg rand_dir_x = 0;        // 0과 1을 미친 듯이 왔다갔다 하는 좌/우 방향 뽑기용 플립플롭
    
    always @(posedge clk_33M) begin
        // 공이 화면 바깥(V_ACTIVE - B_S = 470)에서 생성되지 않게 한계치를 줍니다.
        if (rand_y >= (V_ACTIVE - B_S - 1)) rand_y <= 0; 
        else rand_y <= rand_y + 1;
        
        rand_dir_x <= ~rand_dir_x; // 클럭마다 0, 1, 0, 1 반전
    end


    // ==========================================
    // [ADD] 싱글모드 AI 모듈 인스턴스
    // ==========================================
    wire [1:0] ai_decision;
    ai_module aim(
        .ball_x(ball_x),
        .ball_y(ball_y),
        .ball_dx(b1_dx),
        .ball_dy(b1_dy),
        .paddle_y(p2_y),
        .ai_action(ai_decision)
    );
    
    pong_predict predict_inst(
        .clk_33M(clk_33M),
        .frame_tick(frame_tick),
        .rst_p(rst_p),

        .ball_x(ball_x),
        .ball_y(ball_y),
        .ball_dx(b1_dx),
        .ball_dy(b1_dy),

        .paddle_y(p2_y),
        .rand_y(rand_y),

        .predict_up(predict_up),
        .predict_down(predict_down)
    );

    // ==========================================
    // [ADD] P2 제어 선택 MUX
    // ==========================================
    reg p2_up_ctrl_mux;
    reg p2_down_ctrl_mux;
    
    always @(*) begin
        if(sw_ai_en) begin
            p2_up_ctrl_mux = (ai_decision == 2'b01);
            p2_down_ctrl_mux = (ai_decision == 2'b10);
        end
        else if(predict_mode) begin
            p2_up_ctrl_mux = predict_up;
            p2_down_ctrl_mux = predict_down;
        end
        else begin
            p2_up_ctrl_mux = btn_p2_up;
            p2_down_ctrl_mux = btn_p2_down;
        end
    end
    assign p2_up_ctrl = p2_up_ctrl_mux;
    assign p2_down_ctrl = p2_down_ctrl_mux;


    // ==========================================
    // ⚙️ 5. 게임 물리 엔진 및 로직 업데이트 (동기식 순차 회로)
    // ==========================================
    reg signed [11:0] rel_y; // 공이 패들의 어느 위치에 부딪혔는지 정밀하게 계산하기 위한 변수

    // [초보자 가이드] always 블록 안에서 쓰이는 '<=' (Non-blocking) 기호는 매우 중요합니다!
    // 소프트웨어 코딩처럼 윗 줄이 실행되고 아랫줄이 실행되는 것이 아니라,
    // 클럭이 뛰는 찰나의 순간에 모든 줄의 계산 결과가 '동시에' 각 레지스터(메모리)로 들어갑니다.
    always @(posedge clk_33M) begin
        
        // 사운드 트리거는 소리를 낸 직후 항상 0으로 되돌려 놓습니다. (방아쇠 복구)
        hit_wall <= 0; hit_paddle <= 0; hit_score <= 0;

        // [리셋 로직] 리셋 버튼(rst_p)을 누르면 모든 것을 초기화합니다.
        if (rst_p) begin
            state <= S_PLAY; p1_score <= 0; p2_score <= 0; p1_y <= 210; p2_y <= 210;
            
            // --- 서브 (Serve) 로직 ---
            // 1. 스폰 위치: 중앙 세로선(x = 400 - (공크기/2) = 395)을 따라 랜덤한 높이(rand_y)에서 스폰됩니다.
            ball_y <= rand_y; ball_x <= 395; cur_dx1 <= BALL_INIT_DX; 
            
            // 2. 수평(X) 방향: rand_dir_x에 따라 50% 확률로 왼쪽(-) 또는 오른쪽(+)으로 발사!
            b1_dx <= rand_dir_x ? BALL_INIT_DX : -BALL_INIT_DX; 
            
            // 3. 수직(Y) 방향 [오리지널 메카닉]: 
            // 모니터는 (0,0)이 맨 위고, 숫자가 커질수록 아래로 내려갑니다.
            // 위쪽 절반(235 미만)에서 스폰되면 공이 무조건 아래로 향하게(+DY) 하여 자연스럽게 화면 안쪽으로 던져줍니다.
            b1_dy <= (rand_y < 235) ? BALL_INIT_DY : -BALL_INIT_DY; 
            b1_hit <= 0;
        end 
        
        // [프레임 업데이트] 1초에 60번, 화면을 한 번 다 그렸을 때만 물체들이 움직입니다.
        else if (frame_tick) begin
            
            // 게임이 플레이 중이고, 일시정지 스위치(sw_start)가 켜져 있을 때만 작동
            if (state == S_PLAY && sw_start) begin
                
                // --- 1. 패들 이동 엔진 ---
                // 패들이 화면 맨 위(5)를 뚫고 나가지 않았을 때만 위로(-) 이동 허용.
                // 삼항 연산자(? :)를 써서 대시 버튼이 눌렸으면 10픽셀, 아니면 4픽셀씩 뺍니다.
                
                // P1 위로 이동
                if (btn_p1_up) begin
                    if (p1_y > 5 + (btn_p1_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD))
                        p1_y <= p1_y - (btn_p1_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD);
                    else
                        p1_y <= 5; 
                end
                // P1 아래로 이동
                else if (btn_p1_down) begin
                    if (p1_y < (V_ACTIVE - P_H - 5) - (btn_p1_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD))
                        p1_y <= p1_y + (btn_p1_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD);
                    else
                        p1_y <= (V_ACTIVE - P_H - 5); 
                end
                
                // // P2 위로 이동 
                // if (btn_p2_up) begin
                //     if (p2_y > 5 + (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD))
                //         p2_y <= p2_y - (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD);
                //     else
                //         p2_y <= 5;
                // end
                // // P2 아래로 이동
                // else if (btn_p2_down) begin
                //     if (p2_y < (V_ACTIVE - P_H - 5) - (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD))
                //         p2_y <= p2_y + (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD);
                //     else
                //         p2_y <= (V_ACTIVE - P_H - 5);
                // end

                // ------------------------------------------
                // [MOD] P2 이동부 교체
                // - sw_single_mode=1 : AI 제어
                // - sw_single_mode=0 : 기존 수동 제어
                // ------------------------------------------
                if (p2_up_ctrl) begin
                    if (predict_mode) begin
                        // [ADD] AI 모드 속도 제한
                        if (p2_y > 5 + 3)
                            p2_y <= p2_y - 3;
                        else
                            p2_y <= 5;
                    end
                    else begin
                        // 기존 2인 모드
                        if (p2_y > 5 + (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD))
                            p2_y <= p2_y - (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD);
                        else
                            p2_y <= 5;
                    end
                end
                else if (p2_down_ctrl) begin
                    if (predict_mode) begin
                        // [ADD] AI 모드 속도 제한
                        if (p2_y < (V_ACTIVE - P_H - 5) - 3)
                            p2_y <= p2_y + 3;
                        else
                            p2_y <= (V_ACTIVE - P_H - 5);
                    end
                    else begin
                        // 기존 2인 모드
                        if (p2_y < (V_ACTIVE - P_H - 5) - (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD))
                            p2_y <= p2_y + (btn_p2_dash ? PADDLE_DASH_SPD : PADDLE_BASE_SPD);
                        else
                            p2_y <= (V_ACTIVE - P_H - 5);
                    end
                end

                // --- 2. Ball 이동 및 물리 엔진 ---
                ball_x <= ball_x + b1_dx; // 매 프레임마다 현재 X 좌표에 속도(dx)를 더해서 새 위치로 이동
                ball_y <= ball_y + b1_dy;

                // [벽 충돌 로직] 
                if (ball_y <= 0 && b1_dy < 0) begin 
                    ball_y <= 0;       // 화면 밖으로 못 나가게 좌표 보정
                    b1_dy <= -b1_dy;   // Y축 방향을 마이너스로 뒤집어서 튕겨냄
                    hit_wall <= 1;     // '띡' 하는 벽 충돌음 방아쇠 당김
                end
                // 화면 맨 아래(480 - 공크기10 = 470)에 닿았고, 공이 아래로(b1_dy > 0) 내려갈 때만 반사.
                else if (ball_y >= (V_ACTIVE - B_S) && b1_dy > 0) begin 
                    ball_y <= (V_ACTIVE - B_S); b1_dy <= -b1_dy; hit_wall <= 1; 
                end

                // [P1(왼쪽) 패들 충돌 로직] 
                if (ball_x <= P1_X + P_W && ball_x + B_S >= P1_X && ball_y + B_S >= p1_y && ball_y <= p1_y + P_H && b1_dx < 0) begin
                    ball_x <= P1_X + P_W; // 렉이 걸려도 공이 패들을 뚫지 않게 표면으로 밀어냄
                    hit_paddle <= 1;      // '삑' 하는 경쾌한 패들 타격음 발생
                    
                    // [가속 로직] 정해진 타격 횟수를 채우면 최대 속도 전까지 X축 속력을 +1 올립니다.
                    if (b1_hit < ACCEL_HITS - 1) b1_hit <= b1_hit + 1; 
                    else begin b1_hit <= 0; if (cur_dx1 < BALL_MAX_DX) cur_dx1 <= cur_dx1 + 1; end 
                    
                    b1_dx <= cur_dx1; // 공의 방향을 오른쪽(+)으로 튕겨냅니다. 
                    
                    // [오리지널 8구역(Octant) 반사각 물리 엔진]
                    rel_y = (ball_y + (B_S/2)) - p1_y; 
                    
                    if      (rel_y < 8)  b1_dy <= -4; 
                    else if (rel_y < 15) b1_dy <= -3; 
                    else if (rel_y < 23) b1_dy <= -2; 
                    else if (rel_y < 30) b1_dy <= -1; 
                    else if (rel_y < 38) b1_dy <=  1; 
                    else if (rel_y < 45) b1_dy <=  2; 
                    else if (rel_y < 53) b1_dy <=  3; 
                    else                 b1_dy <=  4; 
                end 
                
                // [P2(오른쪽) 패들 충돌 로직] 
                else if (ball_x + B_S >= P2_X && ball_x <= P2_X + P_W && ball_y + B_S >= p2_y && ball_y <= p2_y + P_H && b1_dx > 0) begin
                    ball_x <= P2_X - B_S; hit_paddle <= 1;
                    
                    if (b1_hit < ACCEL_HITS - 1) b1_hit <= b1_hit + 1; 
                    else begin b1_hit <= 0; if (cur_dx1 < BALL_MAX_DX) cur_dx1 <= cur_dx1 + 1; end
                    
                    b1_dx <= -cur_dx1; // 마이너스를 붙여서 왼쪽으로 튕김!
                    
                    rel_y = (ball_y + (B_S/2)) - p2_y; 
                    
                    if      (rel_y < 8)  b1_dy <= -4; else if (rel_y < 15) b1_dy <= -3; 
                    else if (rel_y < 23) b1_dy <= -2; else if (rel_y < 30) b1_dy <= -1; 
                    else if (rel_y < 38) b1_dy <=  1; else if (rel_y < 45) b1_dy <=  2; 
                    else if (rel_y < 53) b1_dy <=  3; else                 b1_dy <=  4; 
                end

                // --- 3. 득점 판정 및 랜덤 서브 ---
                // 둘 중 한 명이라도 골인 이벤트 발생
                if (p1_scored || p2_scored) begin 
                    
                    // 2개의 독립적인 점수카운터 
                    if (p1_scored && p1_score < win_score) p1_score <= p1_score + 1;
                    if (p2_scored && p2_score < win_score) p2_score <= p2_score + 1;

                    // 게임 종료 판정
                    if ((p1_scored && p1_score == (win_score - 1)) || 
                        (p2_scored && p2_score == (win_score - 1))) begin
                        state <= S_OVER; 
                    end
                    
                    hit_score <= 1; // 득점 효과음 트리거
                    
                    // Ball 리셋 (중앙선의 랜덤 Y 위치로 스폰)
                    ball_y <= rand_y; 
                    ball_x <= 395; 
                    cur_dx1 <= BALL_INIT_DX; 
                    b1_dx <= rand_dir_x ? BALL_INIT_DX : -BALL_INIT_DX; 
                    b1_dy <= (rand_y < 235) ? BALL_INIT_DY : -BALL_INIT_DY; 
                    b1_hit <= 0;
                end
            end
        end
    end

    // ==========================================
    // 🎨 6. VGA 화면 렌더링 (순수 조합 논리 회로 구역)
    // ==========================================
    
    // 🌟 [오리지널 퐁 복원] 하드웨어 7-세그먼트 스코어 렌더러
    function check_score;
        input [9:0] h, v, sx, sy; // 입력 전선: 현재 모니터 전자빔의 X,Y 좌표(h, v)와 숫자를 그릴 시작 좌표(sx, sy)
        input [3:0] val;          // 입력 전선: 현재 점수 (0~9까지 들어옴)
        reg a, b, c, d, e, f, g;  // 내부 전선: 전자계산기 숫자의 7개 획(선)을 켤지 끌지 결정하는 스위치 플래그
        reg is_on;                // 최종 출력: "지금 전자빔이 지나가는 자리에 하얀색을 칠해라!" 라는 최종 명령
        begin
            // 💡 [7-세그먼트 디코더 회로]
            a = (val==0||val==2||val==3||val==5||val==6||val==7||val==8||val==9); // 윗변
            b = (val==0||val==1||val==2||val==3||val==4||val==7||val==8||val==9); // 우측 상단 획
            c = (val==0||val==1||val==3||val==4||val==5||val==6||val==7||val==8||val==9); // 우측 하단 획
            d = (val==0||val==2||val==3||val==5||val==6||val==8||val==9); // 아랫변
            e = (val==0||val==2||val==6||val==8); // 좌측 하단 획
            f = (val==0||val==4||val==5||val==6||val==8||val==9); // 좌측 상단 획
            g = (val==2||val==3||val==4||val==5||val==6||val==8||val==9); // 가운데 가로 변

            is_on = 0; 

            // 📐 [기하학적 렌더링 회로]
            if (a && h >= sx && h < sx+40 && v >= sy && v < sy+10) is_on = 1;
            if (b && h >= sx+30 && h < sx+40 && v >= sy && v < sy+40) is_on = 1;
            if (c && h >= sx+30 && h < sx+40 && v >= sy+40 && v < sy+80) is_on = 1;
            if (d && h >= sx && h < sx+40 && v >= sy+70 && v < sy+80) is_on = 1;
            if (e && h >= sx && h < sx+10 && v >= sy+40 && v < sy+80) is_on = 1;
            if (f && h >= sx && h < sx+10 && v >= sy && v < sy+40) is_on = 1;
            if (g && h >= sx && h < sx+40 && v >= sy+35 && v < sy+45) is_on = 1;

            check_score = is_on; 
        end
    endfunction

    // ------------------------------------------
    // [현대적 추가 기능] WIN / LOSE 텍스트용 도트 매트릭스 렌더러
    // ------------------------------------------
    function [24:0] get_glyph;
        input [4:0] char_code;
        case(char_code)
            10: get_glyph = 25'b10001_10001_10101_11011_10001; // W
            11: get_glyph = 25'b11111_00100_00100_00100_11111; // I
            12: get_glyph = 25'b10001_11001_10101_10011_10001; // N
            13: get_glyph = 25'b10000_10000_10000_10000_11111; // L
            14: get_glyph = 25'b11111_10001_10001_10001_11111; // O
            15: get_glyph = 25'b11111_10000_11111_00001_11111; // S
            16: get_glyph = 25'b11111_10000_11111_10000_11111; // E
            default: get_glyph = 25'd0; 
        endcase
    endfunction

    // 🔍 [도트 매트릭스 확대/출력 회로]
    function check_pixel;
        input [9:0] h, v, sx, sy; input [4:0] char; reg [3:0] cx, cy; reg [24:0] g;
        begin
            // 전자빔(h, v)이 글자를 그릴 40x40 픽셀 정사각형 박스 안에 들어왔다면!
            if (h >= sx && h < sx + 40 && v >= sy && v < sy + 40) begin
                cx = (h - sx) >> 3; 
                cy = (v - sy) >> 3; 
                g = get_glyph(char); 
                check_pixel = g[24 - (cy * 5 + cx)];
            end else check_pixel = 0; 
        end
    endfunction

    // ------------------------------------------
    // 🗺️ 객체 위치 지정 및 화면 합성 (거대한 OR 게이트 연결 작업)
    // ------------------------------------------
    
    // 🌟 P1 점수는 X좌표 300, Y좌표 40에 7-세그먼트로 그립니다.
    wire draw_p1_score = check_score(h_cnt, v_cnt, 300, 40, p1_score); 
    // 🌟 P2 점수는 X좌표 460, Y좌표 40에 7-세그먼트로 그립니다.
    wire draw_p2_score = check_score(h_cnt, v_cnt, 460, 40, p2_score);
    
    // 점수는 '게임이 플레이 중(S_PLAY)'일 때만 화면에 나옵니다.
    wire draw_score = (state == S_PLAY) & (draw_p1_score | draw_p2_score);

    // 승패 텍스트 배치
    wire draw_p1_W = check_pixel(h_cnt, v_cnt, 120, 200, 10); wire draw_p1_I = check_pixel(h_cnt, v_cnt, 170, 200, 11); wire draw_p1_N = check_pixel(h_cnt, v_cnt, 220, 200, 12);
    wire draw_p1_L = check_pixel(h_cnt, v_cnt, 100, 200, 13); wire draw_p1_O = check_pixel(h_cnt, v_cnt, 150, 200, 14); wire draw_p1_S = check_pixel(h_cnt, v_cnt, 200, 200, 15); wire draw_p1_E = check_pixel(h_cnt, v_cnt, 250, 200, 16);

    wire draw_p2_W = check_pixel(h_cnt, v_cnt, 540, 200, 10); wire draw_p2_I = check_pixel(h_cnt, v_cnt, 590, 200, 11); wire draw_p2_N = check_pixel(h_cnt, v_cnt, 640, 200, 12);
    wire draw_p2_L = check_pixel(h_cnt, v_cnt, 520, 200, 13); wire draw_p2_O = check_pixel(h_cnt, v_cnt, 570, 200, 14); wire draw_p2_S = check_pixel(h_cnt, v_cnt, 620, 200, 15); wire draw_p2_E = check_pixel(h_cnt, v_cnt, 670, 200, 16);

    // 🏆 [최적화된 승리/패배 트리거 회로]
    wire p1_win_text = (state == S_OVER && p1_score == win_score) & (draw_p1_W | draw_p1_I | draw_p1_N);
    wire p2_win_text = (state == S_OVER && p2_score == win_score) & (draw_p2_W | draw_p2_I | draw_p2_N);

    // 🧠 [버그 방지턱 적용]
    // 여기서 'p1_score != win_score' 대신 'p1_score < win_score'를 쓰는 이유는 
    // 오버플로우나 에러 상황에서도 안전하게 하드웨어 로직을 묶기 위함입니다.
    wire p1_lose_text = (state == S_OVER && p1_score < win_score) & (draw_p1_L | draw_p1_O | draw_p1_S | draw_p1_E);
    wire p2_lose_text = (state == S_OVER && p2_score < win_score) & (draw_p2_L | draw_p2_O | draw_p2_S | draw_p2_E);
    
    // 화면에 띄울 '모든 글자' 신호를 하나의 선으로 뭉칩니다.
    wire draw_text = draw_score | p1_win_text | p2_win_text | p1_lose_text | p2_lose_text;

    // [오브젝트 렌더링 회로] 전자빔이 패들과 공의 위치(히트박스)를 지나가면 1이 되는 선들입니다.
    wire draw_p1 = (h_cnt >= P1_X && h_cnt < P1_X + P_W && v_cnt >= p1_y && v_cnt < p1_y + P_H);
    wire draw_p2 = (h_cnt >= P2_X && h_cnt < P2_X + P_W && v_cnt >= p2_y && v_cnt < p2_y + P_H);
    wire draw_ball1 = (h_cnt >= ball_x && h_cnt < ball_x + B_S && v_cnt >= ball_y && v_cnt < ball_y + B_S);
    
    // 화면 정중앙(398~402)을 긋는 네트. v_cnt[4]가 1일 때만 그려서, 16픽셀 단위로 끊어지는 완벽한 점선을 만듭니다.
    wire draw_net = (h_cnt >= 398 && h_cnt <= 402 && v_cnt[4] == 1); 
    
    // 공은 게임 플레이 중일 때만 그립니다.
    wire show_ball = (state == S_PLAY) & draw_ball1;
    
    // 🌊 [최종 화면 믹서 (Mixer)] 
    wire draw_any = draw_p1 | draw_p2 | show_ball | draw_net | draw_text;
    
    // 테스트 스위치(sw_test)가 켜지면 무조건 전체를 하얗게 칠합니다.
    wire final_draw = sw_test | draw_any; 

    // 📺 [최종 핀 출력 멀티플렉서(MUX)]
    assign vga_r = (video_on && final_draw) ? 4'hF : 4'h0;
    assign vga_g = (video_on && final_draw) ? 4'hF : 4'h0;
    assign vga_b = (video_on && final_draw) ? 4'hF : 4'h0;

endmodule


