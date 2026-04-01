`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/31/2026 01:44:57 PM
// Design Name: 
// Module Name: Pre
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



module pong_predict(
    input clk_33M,
    input frame_tick,
    input rst_p,

    input signed [11:0] ball_x,
    input signed [11:0] ball_y,
    input signed [4:0]  ball_dx,
    input signed [4:0]  ball_dy,
    input signed [11:0] paddle_y,

    input [8:0] rand_y,

    output reg predict_up,
    output reg predict_down
);

    // -----------------------------
    // 예측 튜닝 파라미터
    // -----------------------------
    parameter P2_X            = 760;
    parameter P_H             = 60;
    parameter B_S             = 10;
    parameter V_ACTIVE        = 480;

    parameter Predict_REACTION_DIV = 2;   // 2프레임마다 1번 판단. 난이도 낮추려면 숫자 증가시키기
    parameter Predict_DEADZONE     = 8;   // 목표 근처 정지 범위. 난이도 낮추려면 숫자 증가 시키기
    parameter Predict_MAX_STEP     = 3;   // 실제 top에서 참고할 최대 이동량
    parameter Predict_ERROR_RANGE  = 10;  // 예측 오차 크기. 난이도 낮추려면 숫자 증가 시키기

    reg [2:0] reaction_cnt = 0;
    reg signed [11:0] target_y;
    reg signed [11:0] predict_y;
    reg signed [11:0] travel_steps;
    reg signed [11:0] error_y;

    always @(posedge clk_33M) begin
        if (rst_p) begin
            predict_up <= 0;
            predict_down <= 0;
            reaction_cnt <= 0;
            target_y <= 210;
        end
        else if (frame_tick) begin
            if (reaction_cnt >= Predict_REACTION_DIV - 1) begin
                reaction_cnt <= 0;

                // 기본값
                predict_up <= 0;
                predict_down <= 0;

                // 공이 오른쪽(P2)으로 올 때만 예측
                if (ball_dx > 0) begin
                    if ((P2_X - (ball_x + B_S)) > 0)
                        travel_steps = (P2_X - (ball_x + B_S)) / ball_dx;
                    else
                        travel_steps = 0;

                    predict_y = ball_y + (ball_dy * travel_steps);

                    // 일부러 오차를 넣어서 너무 완벽하지 않게
                    error_y = $signed({1'b0, rand_y[4:0]}) - Predict_ERROR_RANGE;

                    target_y = predict_y - (P_H/2) + (B_S/2) + error_y;

                    // 화면 범위 제한
                    if (target_y < 5)
                        target_y = 5;
                    else if (target_y > (V_ACTIVE - P_H - 5))
                        target_y = (V_ACTIVE - P_H - 5);
                end
                else begin
                    // 공이 멀어지면 중앙 복귀
                    target_y = 210;
                end

                // 위/아래 판단
                if (paddle_y > target_y + Predict_DEADZONE) begin
                    predict_up <= 1;
                    predict_down <= 0;
                end
                else if (paddle_y < target_y - Predict_DEADZONE) begin
                    predict_up <= 0;
                    predict_down <= 1;
                end
                else begin
                    predict_up <= 0;
                    predict_down <= 0;
                end
            end
            else begin
                reaction_cnt <= reaction_cnt + 1;
            end
        end
    end

endmodule
module pong_predict(
    input clk_33M,
    input frame_tick,
    input rst_p,

    input signed [11:0] ball_x,
    input signed [11:0] ball_y,
    input signed [4:0]  ball_dx,
    input signed [4:0]  ball_dy,
    input signed [11:0] paddle_y,

    input [8:0] rand_y,

    output reg predict_up,
    output reg predict_down
);

    // -----------------------------
    // 예측 튜닝 파라미터
    // -----------------------------
    parameter P2_X            = 760;
    parameter P_H             = 60;
    parameter B_S             = 10;
    parameter V_ACTIVE        = 480;

    parameter Predict_REACTION_DIV = 2;   // 2프레임마다 1번 판단. 난이도 낮추려면 숫자 증가시키기
    parameter Predict_DEADZONE     = 8;   // 목표 근처 정지 범위. 난이도 낮추려면 숫자 증가 시키기
    parameter Predict_MAX_STEP     = 3;   // 실제 top에서 참고할 최대 이동량
    parameter Predict_ERROR_RANGE  = 10;  // 예측 오차 크기. 난이도 낮추려면 숫자 증가 시키기

    reg [2:0] reaction_cnt = 0;
    reg signed [11:0] target_y;
    reg signed [11:0] predict_y;
    reg signed [11:0] travel_steps;
    reg signed [11:0] error_y;

    always @(posedge clk_33M) begin
        if (rst_p) begin
            predict_up <= 0;
            predict_down <= 0;
            reaction_cnt <= 0;
            target_y <= 210;
        end
        else if (frame_tick) begin
            if (reaction_cnt >= Predict_REACTION_DIV - 1) begin
                reaction_cnt <= 0;

                // 기본값
                predict_up <= 0;
                predict_down <= 0;

                // 공이 오른쪽(P2)으로 올 때만 예측
                if (ball_dx > 0) begin
                    if ((P2_X - (ball_x + B_S)) > 0)
                        travel_steps = (P2_X - (ball_x + B_S)) / ball_dx;
                    else
                        travel_steps = 0;

                    predict_y = ball_y + (ball_dy * travel_steps);

                    // 일부러 오차를 넣어서 너무 완벽하지 않게
                    error_y = $signed({1'b0, rand_y[4:0]}) - Predict_ERROR_RANGE;

                    target_y = predict_y - (P_H/2) + (B_S/2) + error_y;

                    // 화면 범위 제한
                    if (target_y < 5)
                        target_y = 5;
                    else if (target_y > (V_ACTIVE - P_H - 5))
                        target_y = (V_ACTIVE - P_H - 5);
                end
                else begin
                    // 공이 멀어지면 중앙 복귀
                    target_y = 210;
                end

                // 위/아래 판단
                if (paddle_y > target_y + Predict_DEADZONE) begin
                    predict_up <= 1;
                    predict_down <= 0;
                end
                else if (paddle_y < target_y - Predict_DEADZONE) begin
                    predict_up <= 0;
                    predict_down <= 1;
                end
                else begin
                    predict_up <= 0;
                    predict_down <= 0;
                end
            end
            else begin
                reaction_cnt <= reaction_cnt + 1;
            end
        end
    end

endmodule
