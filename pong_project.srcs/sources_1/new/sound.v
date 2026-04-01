`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/31/2026 09:39:13 AM
// Design Name: 
// Module Name: sound
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


//사운드 모듈
//특정 사운드에 대해 펄스가 들어오면 그 사운드를 재생하는 방식
//수직 주사 카운터와 직결되어 동작하는 방식은 오리지널 퐁과 같음, 다만 주파수가 오리지널 퐁과 달라 음높이는 조금 다름
module pong_sound(
    input clk_33M,      // 33.3MHz 메인 픽셀 클럭
    input frame_tick,   // 1프레임(1/60초)마다 한 번씩 1이 되는 신호 (시간 잴 때 사용)
    input [9:0] v_cnt,  // [핵심] 화면의 Y좌표 카운터. 이 신호 자체가 훌륭한 주파수 파형입니다.
    input hit_wall,     // 벽에 부딪혔다는 펄스 (1클럭 동안만 1)
    input hit_paddle,   // 패들에 부딪혔다는 펄스
    input hit_score,    // 득점했다는 펄스
    output audio_out    // 스피커로 나가는 최종 구형파 신호
);

    // [초보자 가이드] reg는 전원이 꺼지기 전까지 값을 기억하는 '플립플롭(메모리)' 회로입니다.
    reg [4:0] duration = 0;   // 소리가 얼마나 오래 날지 기억하는 타이머
    reg [1:0] current_snd = 0; // 지금 무슨 소리를 내야 하는지 기억 (1:벽, 2:패들, 3:득점)

    // [초보자 가이드] always @(posedge)는 클럭 신호가 0에서 1로 뛸 때마다 내부 로직을 동시에 실행합니다.
    always @(posedge clk_33M) begin
        
        // 어떤 신호가 발생했는지 확인하고, 타이머와 소리 종류를 세팅합니다.
        if (hit_score) begin
            duration <= 16;      // 16프레임 (약 250ms) 동안 소리 재생
            current_snd <= 3;    // 득점 소리 모드 켜기
        end else if (hit_paddle) begin
            duration <= 6;       // 6프레임 (약 100ms) 동안 소리 재생
            current_snd <= 2;    // 패들 소리 모드 켜기
        end else if (hit_wall) begin
            duration <= 1;       // 1프레임 (약 16ms) 동안 아주 짧게 재생
            current_snd <= 1;    // 벽 소리 모드 켜기
        end 
        
        // 이벤트가 없고, 소리를 내야 하는 시간(duration)이 남아있다면
        else if (frame_tick && duration > 0) begin
            duration <= duration - 1; // 1프레임 지날 때마다 타이머를 1씩 깎습니다.
        end 
        
        // 타이머가 다 닳아서 0이 되면 소리를 끕니다.
        else if (duration == 0) begin
            current_snd <= 0;
        end
    end

    // 🌟 [100% 오리지널 아타리 퐁 하드웨어 결선 방식]
    // 31.5kHz의 수평 주파수를 나누는 v_cnt를 오리지널 주파수(491Hz, 245Hz)에 맞춰 정확히 매핑했습니다.
    assign audio_out = (current_snd == 1) ? v_cnt[6] : // 벽 충돌: 약 246.6 Hz (오리지널 32V 핀과 동일)
                       (current_snd == 2) ? v_cnt[5] : // 패들 충돌: 약 493.2 Hz (오리지널 16V 핀과 동일)
                       (current_snd == 3) ? v_cnt[5] : // 득점: 패들과 완벽히 동일한 주파수 (오리지널과 동일하게 길게 재생만 됨)
                       1'b0;//소리 꺼짐
endmodule

