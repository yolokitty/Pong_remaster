`timescale 1ns / 1ps

module ai_module(
    input signed [11:0] ball_x, ball_y,     
    input signed [4:0]  ball_dx, ball_dy,
    input signed [11:0] paddle_y,
    output [1:0] ai_action          // 0:정지, 1:위, 2:아래
);

    // --- 1. 입력 매핑 ---
    // 32비트 signed로 넉넉하게 확장하여 연산 중 오버플로우를 막습니다.
    wire signed [31:0] in0 = ball_x;
    wire signed [31:0] in1 = ball_y;
    wire signed [31:0] in2 = ball_dx;
    wire signed [31:0] in3 = ball_dy;
    wire signed [31:0] in4 = paddle_y;

    // --- 2. Hidden Layer (fc1: 5 inputs -> 8 nodes) ---
    // 💡 [수정됨] 파이썬의 정규화 비율(/800, /480, /10)을 그대로 적용했습니다.
    // 💡 [수정됨] 투볼용 10개 입력 가중치에서 싱글볼용(0,1,2,3,8번)만 솎아냈습니다.
    wire signed [31:0] h0_pre = (in0 * 15)/800 + (in1 * -51)/480 + (in2 * 75)/10 + (in3 * -39)/10 + (in4 * -5)/480 - 65;
    wire signed [31:0] h1_pre = (in0 * 20)/800 + (in1 * -181)/480 + (in2 * 50)/10 + (in3 * 373)/10 + (in4 * -162)/480 - 223;
    wire signed [31:0] h2_pre = (in0 * -29)/800 + (in1 * -121)/480 + (in2 * 290)/10 + (in3 * 374)/10 + (in4 * -257)/480 - 167;
    wire signed [31:0] h3_pre = (in0 * 8)/800 + (in1 * -542)/480 + (in2 * 94)/10 + (in3 * 20)/10 + (in4 * -464)/480 + 164;
    wire signed [31:0] h4_pre = (in0 * -526)/800 + (in1 * 86)/480 + (in2 * -96)/10 + (in3 * 101)/10 + (in4 * 151)/480 + 535;
    wire signed [31:0] h5_pre = (in0 * -721)/800 + (in1 * 103)/480 + (in2 * -209)/10 + (in3 * 73)/10 + (in4 * 155)/480 + 356;
    wire signed [31:0] h6_pre = (in0 * 11)/800 + (in1 * -183)/480 + (in2 * 127)/10 + (in3 * -13)/10 + (in4 * -111)/480 + 41;
    wire signed [31:0] h7_pre = (in0 * -188)/800 + (in1 * 11)/480 + (in2 * -148)/10 + (in3 * -53)/10 + (in4 * -12)/480 - 35;

    // ReLU 활성화 함수 
    // (0보다 작으면 0으로, 크면 8비트 시프트하여 *256 스케일을 원래대로 복구)
    wire signed [31:0] h0 = (h0_pre > 0) ? h0_pre >>> 8 : 0;
    wire signed [31:0] h1 = (h1_pre > 0) ? h1_pre >>> 8 : 0;
    wire signed [31:0] h2 = (h2_pre > 0) ? h2_pre >>> 8 : 0;
    wire signed [31:0] h3 = (h3_pre > 0) ? h3_pre >>> 8 : 0;
    wire signed [31:0] h4 = (h4_pre > 0) ? h4_pre >>> 8 : 0;
    wire signed [31:0] h5 = (h5_pre > 0) ? h5_pre >>> 8 : 0;
    wire signed [31:0] h6 = (h6_pre > 0) ? h6_pre >>> 8 : 0;
    wire signed [31:0] h7 = (h7_pre > 0) ? h7_pre >>> 8 : 0;

    // --- 3. Output Layer (fc2: 8 hidden -> 3 outputs) ---
    // 추출한 fc2 가중치를 적용합니다. (여기서 나오는 결과는 최종 비교만 하므로 스케일 복구가 필요 없습니다)
    wire signed [31:0] out0 = (h0*77) + (h1*-152) + (h2*866) + (h3*433) + (h4*502) + (h5*-444) + (h6*1339) + (h7*306) - 460; // 정지
    wire signed [31:0] out1 = (h0*-9) + (h1*-211) + (h2*1393) + (h3*487) + (h4*471) + (h5*-414) + (h6*1427) + (h7*284) - 444;  // 위
    wire signed [31:0] out2 = (h0*49) + (h1*45) + (h2*1314) + (h3*412) + (h4*474) + (h5*-419) + (h6*1169) + (h7*290) - 441;  // 아래

    // --- 4. Argmax (가장 큰 출력값을 가진 동작 선택) ---
    assign ai_action = (out1 > out0 && out1 > out2) ? 2'b01 : // 위로 이동
                       (out2 > out0 && out2 > out1) ? 2'b10 : // 아래로 이동
                                                      2'b00;  // 정지
endmodule