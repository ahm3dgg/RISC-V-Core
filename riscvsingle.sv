module testbench();
  logic        clk;
  logic        reset;

  logic [31:0] WriteData, DataAdr;
  logic        MemWrite;

  // instantiate device to be tested
  top dut(clk, reset, WriteData, DataAdr, MemWrite);
  
  // initialize test
  initial
    begin
      reset <= 1; # 22; reset <= 0;
    end

  // generate clock to sequence tests
  always
    begin
      clk <= 1; # 5; clk <= 0; # 5;
    end

  // check results
  always @(negedge clk)
    begin
      if(MemWrite) begin
        if(DataAdr === 100 & WriteData === 25) begin
          $display("Your CPU is working <3");
          $stop;
        end else if (DataAdr !== 96) begin
          $display("Simulation failed");
          $stop;
        end
      end
    end
endmodule

module top(input logic clk, reset, 
		output logic [31:0] WriteData, DataAddr, 
		output logic MemWrite); 

	logic [31:0] PC, Instr, ReadData; 	
	
	riscvsingle rvsingle(clk, reset, 
		PC, Instr, MemWrite, DataAddr, 
		WriteData, ReadData); 

	imem imem(PC, Instr); 
	dmem dmem(clk, MemWrite, DataAddr, WriteData, ReadData); 
endmodule 

module riscvsingle(input logic clk, reset, 
									output logic [31:0] PC, 
									input logic [31:0] Instr, 
									output logic MemWrite, 
									output logic [31:0] ALUResult, WriteData, 
									input logic [31:0] ReadData); 

		logic ALUSrc, RegWrite, Jump, Zero; 
		logic [1:0] ResultSrc, ImmSrc; 
		logic [2:0] ALUControl; 
		
		controller c(Instr[6:0], Instr[14:12], Instr[30], 
					Zero, ResultSrc, MemWrite, PCSrc, 
					ALUSrc, RegWrite, Jump, ImmSrc, ALUControl); 
		
		datapath dp(clk, reset, ResultSrc, PCSrc, 
								ALUSrc, RegWrite, ImmSrc, ALUControl, Zero, 
								PC, Instr, ALUResult, WriteData, ReadData); 
endmodule 

module controller(input logic [6:0] op, 
						input logic [2:0] funct3, 
						input logic funct7b5, 
						input logic Zero, 
						output logic [1:0] ResultSrc, 
						output logic MemWrite, 
						output logic PCSrc, ALUSrc, 
						output logic RegWrite, Jump, 
						output logic [1:0] ImmSrc, 
						output logic [2:0] ALUControl); 

		logic [1:0] ALUOp;
		logic Branch; 

		maindec md(op, ResultSrc, MemWrite, Branch, ALUSrc, RegWrite, Jump, ImmSrc, ALUOp); 
		aludec ad(op[5], funct3, funct7b5, ALUOp, ALUControl); 
		assign PCSrc = Branch & Zero | Jump;
endmodule 

module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               output logic       MemWrite,
               output logic       Branch, ALUSrc,
               output logic       RegWrite, Jump,
               output logic [1:0] ImmSrc,
               output logic [1:0] ALUOp);

  logic [10:0] controls;

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump} = controls;

  always_comb
    case(op)
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump
      7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // lw
      7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // sw
      7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // R-type 
      7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // beq
      7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // I-type ALU
      7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; // jal
      default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // non-implemented instruction
    endcase
endmodule

module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [2:0] ALUControl);

  logic  RtypeSub;
  assign RtypeSub = funct7b5 & opb5;  // TRUE for R-type subtract instruction

  always_comb
    case(ALUOp)
      2'b00:                ALUControl = 3'b000; // addition
      2'b01:                ALUControl = 3'b001; // subtraction
      default: case(funct3) // R-type or I-type ALU
                 3'b000:  if (RtypeSub) 
                            ALUControl = 3'b001; // sub
                          else          
                            ALUControl = 3'b000; // add, addi
                 3'b010:    ALUControl = 3'b101; // slt, slti
                 3'b110:    ALUControl = 3'b011; // or, ori
                 3'b111:    ALUControl = 3'b010; // and, andi
                 default:   ALUControl = 3'bxxx; // ???
               endcase
    endcase
endmodule

module datapath(input logic clk, reset, 
								input logic [1:0] ResultSrc, 
								input logic PCSrc, ALUSrc, 
								input logic RegWrite, 
								input logic [1:0] ImmSrc, 
								input logic [2:0] ALUControl, 
								output logic Zero, 
								output logic [31:0] PC, 
								input logic [31:0] Instr, 
								output logic [31:0] ALUResult, WriteData, 
								input logic [31:0] ReadData); 
		
			logic [31:0] PCNext, PCPlus4, PCTarget; 
			logic [31:0] ImmExt; 
			logic [31:0] SrcA, SrcB; 
			logic [31:0] Result; 

			// next PC Logic 
			flopr #(32) pcreg(clk, reset, PCNext, PC); 
			adder pcadd4(PC, 32'd4, PCPlus4); 
			adder pcaddbranch(PC, ImmExt, PCTarget); 
			mux2 #(32) pcmux(PCPlus4, PCTarget, PCSrc, PCNext); 
			
			// register file logic 
			regfile rf(clk, RegWrite, Instr[19:15], Instr[24:20], Instr[11:7], Result, SrcA, WriteData);
			extend ext(Instr[31:7], ImmSrc, ImmExt); 
			
			// ALU Logic 
			mux2 #(32) srcbmux(WriteData, ImmExt, ALUSrc, SrcB); 
			alu alu(SrcA, SrcB, ALUControl, ALUResult, Zero); 
			mux3 #(32) resultmux(ALUResult, ReadData, PCPlus4, ResultSrc, Result); 
endmodule 

module regfile(input logic clk, 
		input logic we3, 
		input logic [4:0] a1, a2, a3, 
		input logic [31:0] wd3, 
		output logic [31:0] rd1, rd2); 
			
	logic [31:0] rf[31:0]; 
	
	always_ff @(posedge clk)
		if(we3) rf[a3] <= wd3; 

	assign rd1 = (a1 != 0) ? rf[a1] : 0; 
	assign rd2 = (a2 != 0) ? rf[a2] : 0;  
endmodule 

module adder (
		input logic [31:0] a, 
		input logic [31:0] b, 
		output logic [31:0] c); 

		assign c = a + b; 
endmodule 

module extend(input logic [31:7] instr, input logic [1:0] immsrc, output logic [31:0] immext); 
		always_comb
			case(immsrc)
			// I-type 
      2'b00:   immext = {{20{instr[31]}}, instr[31:20]};  
      // S-type (stores)
      2'b01:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; 
      // B-type (branches)
      2'b10:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; 
      // J-type (jal)
      2'b11:   immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; 
      default: immext = 32'bx; // undefined
			endcase 
endmodule 

module flopr #(parameter WIDTH = 8)
					(input logic clk, reset, 
					 input logic [WIDTH-1:0] d, 
					 output logic [WIDTH-1:0] q); 
		always_ff @(posedge clk, posedge reset)
			if(reset) q <= 0; 
			else q <= d; 
endmodule 

module mux3 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, d2,
              input  logic [1:0]       s, 
              output logic [WIDTH-1:0] y);

  assign y = s[1] ? d2 : (s[0] ? d1 : d0); 
endmodule

module mux2 #(parameter WIDTH = 8)
				(input logic [WIDTH-1:0] d0, d1,
				 input logic s, 
				 output logic [WIDTH-1:0] y); 
		assign y = s ? d1 : d0; 
endmodule 

module imem(input logic [31:0] a, output logic [31:0] rd);
	logic [31:0] RAM[63:0];  // Instruction Memory Size: 64*4 = 256 Bytes 
	initial $readmemh("riscvtest.txt", RAM); 
	assign rd = RAM[a[31:2]];
endmodule 

// clk: Clock
// we: Write Enable
// a: address
// wd: Write Data Port
// rd: Read Data Port
module dmem(input logic clk, MemWrite, 
			input logic [31:0] DataAddr, WriteData, 
			output logic [31:0] ReadData); 

		logic [31:0] RAM[63:0]; 

		assign ReadData = RAM[DataAddr[31:2]]; // word aligned 

		always_ff @(posedge clk)
			if(MemWrite) RAM[a[31:2]] <= WriteData; 
endmodule 

module alu(input logic [31:0] a, b,
						input logic [2:0] alucontrol,
						output logic [31:0] result,
						output logic zero); 

	logic [31:0] condinvb, sum; 
	logic v;		// overflow 
	logic isAddSub; 	// true when is add or subtract op

	assign condinvb = alucontrol[0] ? ~b : b; 
	assign sum = a + condinvb + alucontrol[0]; 	
	assign isAddSub = (alucontrol == 3'b000) || (alucontrol == 3'b001);

	always_comb 
		case (alucontrol)
			3'b000: result = sum;  // add 
			3'b001: result = sum; // sub
			3'b010: result = a & b; // and 
			3'b011: result = a | b; // or 
			3'b100: result = a ^ b; // xor 
			3'b101: result = sum[31] ^ v; // slt 
			3'b110: result = a << b[4:0]; // sll 
			3'b111: result = a >> b[4:0]; // srl 
			default: result = 32'bx; 
		endcase 

	assign zero = (result == 31'b0);
	assign v =  ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
endmodule