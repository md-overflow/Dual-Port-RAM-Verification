module ram_4096 ( clk,
                  data_in,
                  rd_address,
                  wr_address,
                  read,
                  write,
                  data_out);

   parameter RAM_WIDTH=64,
             RAM_DEPTH=4096,
             ADDR_SIZE=12;


   input clk;                          // RAM Clock
   input [RAM_WIDTH-1 : 0] data_in;    // Data Input
   input [ADDR_SIZE-1 : 0] rd_address; // Read Address
   input [ADDR_SIZE-1 : 0] wr_address; // Write Address
   input read;                         // Read Control
   input write;                        // Write Control


   output [RAM_WIDTH-1 : 0] data_out;  // Data Output


   reg [RAM_WIDTH-1 : 0] data_out;  

   // Memory
   reg [RAM_WIDTH-1 : 0] memory [RAM_DEPTH-1 : 0];

   //Read Logic
   always @ (posedge clk)
     if(write)
     	 memory[wr_address] <= data_in; 

   //Write Logic
   always @ (posedge clk)
     if(read)
		 data_out <= memory[rd_address];
      else
         data_out <= 64'bz;
  
endmodule:ram_4096

//--------------Dual-port RAM Interface-----------------
interface ram_if(input bit clk);
  logic [63:0] data_in;
  logic [63:0] data_out;
  logic [11:0] rd_address;
  logic [11:0] wr_address;
  logic read;
  logic write;
  
  clocking wr_drv_cb @(posedge clk);
    default input #1 output #1;
    output data_in;
    output wr_address;
    output write;
  endclocking: wr_drv_cb
  
  clocking rd_drv_cb @(posedge clk);
    default input #1 output #1;
    output rd_address;
    output read;
  endclocking: rd_drv_cb
  
  clocking wr_mon_cb @(posedge clk);
    default input #1 output #1;
    input data_in;
    input wr_address;
    input write;
  endclocking: wr_mon_cb
  
  clocking rd_mon_cb @(posedge clk);
    default input #1 output #1;
    input data_out;
    input rd_address;
    input read;
  endclocking: rd_mon_cb
  
  modport WR_DRV_MP(clocking wr_drv_cb);
  modport RD_DRV_MP(clocking rd_drv_cb);
  modport WR_MON_MP(clocking wr_mon_cb);
  modport RD_MON_MP(clocking rd_mon_cb);
    
endinterface: ram_if
    
package ram_pkg;
    int no_of_transactions;
endpackage: ram_pkg
    
    //---------------Transaction class----------------
class ram_trans;
  rand bit[63:0] data;
  rand bit[11:0] rd_address;
  rand bit[11:0] wr_address;
  rand bit read;
  rand bit write;
  
  logic [63:0] data_out;
  
  static int trans_id;
  
  static int no_of_read_trans;  
  static int no_of_write_trans;
  static int no_of_RW_trans;
  
  constraint VALID_ADDR{rd_address!=wr_address;}
  constraint VALID_CNTRL{{read,write}!=2'b00;}
  constraint VALID_DATA{data inside{[1:4294]};}
  
  function void post_randomize();
    if(this.write==1 && this.read==0)
      no_of_write_trans++;
    if(this.write==0 && this.read==1)
      no_of_read_trans++;
    if(this.write==1 && this.read==1)
      no_of_RW_trans++;
    
    this.display("\tRANDOMIZED DATA");
  endfunction: post_randomize
  
  virtual function void display(input string message);
    $display("=============================================================");
    $display("%s",message);
    if(message=="\tRANDOMIZED DATA")
        begin
          $display("\t______________________________");
          $display("\tTransaction No: \t%0d",trans_id);
          $display("\tRead Transaction No: \t%0d", no_of_read_trans);
          $display("\tWrite Transaction No: \t%0d", no_of_write_trans);
          $display("\tRW Transaction No: \t%0d", no_of_RW_trans);
          $display("\t______________________________");
        end
    $display("\tRead\t\t= %0d",read);
    $display("\twrite\t\t= %0d",write);
    $display("\tRead_Address \t= %0d",rd_address);
    $display("\tWrite_Address\t= %0d", wr_address);
    $display("\tData_in\t\t= %0d",data);
    $display("\tData_out\t= %0d",data_out);
    $display("=============================================================");
  endfunction: display
  
  virtual function bit compare(input ram_trans rcv, output string message);
    compare = '0;
    begin
      if(this.rd_address != rcv.rd_address)
        begin
          $display($time);
          $display("--------- ADDRESS MISMATCH -----------");
          return (0);
        end
      if(this.data_out != rcv.data_out)
        begin
          $display($time);
          $display("--------- DATA MISMATCH -----------");
          return (0);
        end
      begin
        message = "SUCCESSFULLY COMPARED";
        return (1);
      end
    end
    
  endfunction: compare
  
endclass: ram_trans
    
    //----------------Generator Class---------------------
import ram_pkg::*;
class ram_gen;
  ram_trans gen_trans;
  ram_trans data2send;
  
  mailbox #(ram_trans) gen2wr;
  mailbox #(ram_trans) gen2rd;
  
  function new(mailbox #(ram_trans) gen2rd,
               mailbox #(ram_trans) gen2wr);
    this.gen2rd = gen2rd;
	this.gen2wr = gen2wr;
    this.gen_trans = new();
  endfunction:new
  
  virtual task start();
    fork
      begin
        for(int i=0; i<no_of_transactions; i++)
          begin
            gen_trans.trans_id++;
            assert(gen_trans.randomize());
            data2send = new gen_trans;
            //data2send.display("GENERATED DATA");
            gen2rd.put(data2send);
            gen2wr.put(data2send);
          end
      end
    join_none
  endtask: start
  
endclass: ram_gen
    
    //--------------------Write Driver--------------------
    
class ram_write_drv;
  virtual ram_if.WR_DRV_MP wr_drv_if;
  
  ram_trans data2duv;
  
  mailbox #(ram_trans) gen2wr;
  
  function new(virtual ram_if.WR_DRV_MP wr_drv_if,
               mailbox #(ram_trans) gen2wr);
    this.wr_drv_if = wr_drv_if;
    this.gen2wr = gen2wr;
  endfunction: new
  
  virtual task start();
    fork
      begin
        gen2wr.get(data2duv);
        drive();
        //data2duv.display("WRITE DATA DRIVEN");
      end
    join_none
  endtask: start
  
  virtual task drive();
    @(wr_drv_if.wr_drv_cb);
    if(data2duv.write == 1)
      begin
        wr_drv_if.wr_drv_cb.data_in 	<= data2duv.data;
    	wr_drv_if.wr_drv_cb.wr_address  <= data2duv.wr_address;
    	wr_drv_if.wr_drv_cb.write		<= data2duv.write;
      end
    repeat(2) @(wr_drv_if.wr_drv_cb);
    wr_drv_if.wr_drv_cb.write <= '0;
  endtask: drive
  
endclass: ram_write_drv
    
    //--------------------Read Driver--------------------
    
class ram_read_drv;
  virtual ram_if.RD_DRV_MP rd_drv_if;
  
  ram_trans data2duv;
  
  mailbox #(ram_trans) gen2rd;
  
  function new(virtual ram_if.RD_DRV_MP rd_drv_if,
               mailbox #(ram_trans) gen2rd);
    this.rd_drv_if = rd_drv_if;
    this.gen2rd = gen2rd;
  endfunction: new
  
  virtual task start();
    fork
      begin
        gen2rd.get(data2duv);
        drive();
        //data2duv.display("READ DATA DRIVEN");
      end
    join_none
  endtask: start
  
  virtual task drive();
      @(rd_drv_if.rd_drv_cb);
    
      rd_drv_if.rd_drv_cb.rd_address <= data2duv.rd_address;
      rd_drv_if.rd_drv_cb.read       <= data2duv.read;    
        
      repeat(2) @(rd_drv_if.rd_drv_cb);
      rd_drv_if.rd_drv_cb.read<='0;
   endtask: drive
  
endclass: ram_read_drv
    
    //-------------------Read Monitor-------------------
    
class ram_read_mon;
  virtual ram_if.RD_MON_MP rd_mon_if;
  
  int rd_mon_data;
  event done;
  
  ram_trans data2rm;
  ram_trans data2sb;
  ram_trans rddata;
  
  mailbox #(ram_trans) mon2rm;
  mailbox #(ram_trans) mon2sb;
  
  function new(virtual ram_if.RD_MON_MP rd_mon_if,
               mailbox #(ram_trans) mon2rm,
               mailbox #(ram_trans) mon2sb);
    this.rd_mon_if = rd_mon_if;
    this.mon2rm = mon2rm;
    this.mon2sb = mon2sb;
    this.rddata = new();
  endfunction: new
  
  virtual task monitor();
    @(rd_mon_if.rd_mon_cb);
    wait(rd_mon_if.rd_mon_cb.read == 1)
    @(rd_mon_if.rd_mon_cb);
    begin
      rd_mon_data++;
      rddata.read		= rd_mon_if.rd_mon_cb.read;
      rddata.rd_address = rd_mon_if.rd_mon_cb.rd_address;
      rddata.data_out 	= rd_mon_if.rd_mon_cb.data_out;
      rddata.display("DATA FROM READ MONITOR");
    end
    $display("####### rd_mon_data: %0d ##########", rd_mon_data);
    if(rd_mon_data >= no_of_transactions-rddata.no_of_write_trans)
         ->done;
    
  endtask: monitor
  
  virtual task start();
    fork 
      forever
        begin
          monitor();
          data2sb = new rddata;
          data2rm = new rddata;
          mon2rm.put(data2rm);
          mon2sb.put(data2sb);
        end
    join_none
  endtask:start
  
endclass: ram_read_mon
    
	//-------------------Write Monitor-------------------
    
class ram_write_mon;
  virtual ram_if.WR_MON_MP wr_mon_if;
  
  ram_trans data2rm;
  ram_trans wrdata;
  
  mailbox #(ram_trans) mon2rm;
  
  function new(virtual ram_if.WR_MON_MP wr_mon_if,
               mailbox #(ram_trans) mon2rm);
    this.wr_mon_if = wr_mon_if;
    this.mon2rm = mon2rm;
    this.wrdata = new();
  endfunction: new
  
  virtual task monitor();
    @(wr_mon_if.wr_mon_cb);
    wait(wr_mon_if.wr_mon_cb.write == 1);
    @(wr_mon_if.wr_mon_cb);
    wrdata.write		= wr_mon_if.wr_mon_cb.write;
    wrdata.wr_address	= wr_mon_if.wr_mon_cb.wr_address;
    wrdata.data			= wr_mon_if.wr_mon_cb.data_in;
    wrdata.display("DATA FROM WRITE MONITOR");
  endtask: monitor
  
  virtual task start();
    fork
      forever
        begin
          monitor();
          data2rm = new wrdata;
          mon2rm.put(data2rm);
        end
    join_none
  endtask: start
    
endclass: ram_write_mon

	//--------------------- Top ------------------------
    
module top();
  import ram_pkg::*;
  reg clock;
  ram_if DUV_IF(clock);
  
  ram_gen gen_h;
  ram_write_drv wr_drv_h;
  ram_read_drv rd_drv_h;
  ram_write_mon wr_mon_h;
  ram_read_mon rd_mon_h;
  
  mailbox #(ram_trans) gen2wr = new();
  mailbox #(ram_trans) gen2rd = new(); 
  mailbox #(ram_trans) mon2rm = new();
  mailbox #(ram_trans) mon2sb = new();
  
  ram_4096 RAM(.clk(clock),
               .data_in(DUV_IF.data_in),
               .data_out(DUV_IF.data_out),
               .wr_address(DUV_IF.wr_address),
               .rd_address(DUV_IF.rd_address),
               .read(DUV_IF.read),
               .write(DUV_IF.write));
  
  initial begin
    clock = 0;
    forever #5 clock = ~clock;
  end
  
  initial begin
    gen_h = new(gen2rd, gen2wr);
    wr_drv_h = new(DUV_IF, gen2wr);
    rd_drv_h = new(DUV_IF, gen2rd);
    wr_mon_h = new(DUV_IF, mon2rm);
    rd_mon_h = new(DUV_IF, mon2rm, mon2sb);
    no_of_transactions = 4;
    gen_h.start();
    wr_drv_h.start();
    rd_drv_h.start();
    wr_mon_h.start();
    rd_mon_h.start();
    wait(rd_mon_h.done.triggered);
    $finish;
  end
      
endmodule:top