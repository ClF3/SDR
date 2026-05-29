create_clock -name adc1_clk -period 4.000 [get_ports adc1_clk_p_0]

# These clocks are normally generated inside the Zynq UltraScale+ block design.
# Keep them constrained here when running the RTL top as a standalone project.
create_clock -name s_axi_aclk -period 10.000 [get_ports s_axi_aclk]
create_clock -name adc_ref_clk -period 4.000 [get_ports adc_ref_clk]
create_clock -name spi_clk_50m -period 20.000 [get_ports spi_clk_50m]
