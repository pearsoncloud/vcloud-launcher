require 'spec_helper'
require 'pp'
require 'erb'
require 'ostruct'
require 'vcloud/tools/tester'

describe Vcloud::Launcher::Launch do
  context "with minimum input setup" do
    it "should provision vapp with single vm" do
      parameters = Vcloud::Tools::Tester::
        TestParameters.new('vcloud_tools_testing_config.yaml')
      vapp_name = "vapp-vcloud-tools-tests-#{Time.now.strftime('%s')}"
      test_data_1 = {
        vapp_name: vapp_name,
        vdc_name: parameters.vdc_name,
        catalog: parameters.catalog,
        vapp_template: parameters.catalog_item
      }
      minimum_data_erb = File.join(File.dirname(__FILE__),
        'data/minimum_data_setup.yaml.erb')
      @minimum_data_yaml = ErbHelper.convert_erb_template_to_yaml(test_data_1, minimum_data_erb)
      @fog_interface = Vcloud::Fog::ServiceInterface.new

      Vcloud::Launcher::Launch.new.run(@minimum_data_yaml, {"dont-power-on" => true})

      vapp_query_result = @fog_interface.get_vapp_by_name_and_vdc_name(vapp_name, parameters.vdc_name)
      @provisioned_vapp_id = vapp_query_result[:href].split('/').last
      provisioned_vapp = @fog_interface.get_vapp @provisioned_vapp_id

      provisioned_vapp.should_not be_nil
      provisioned_vapp[:name].should == vapp_name
      provisioned_vapp[:Children][:Vm].count.should == 1
    end

    after(:each) do
      unless ENV['VCLOUD_TOOLS_RSPEC_NO_DELETE_VAPP']
        File.delete @minimum_data_yaml
        @fog_interface.delete_vapp(@provisioned_vapp_id).should == true
      end
    end
  end

  context "happy path" do
    before(:all) do
      parameters = Vcloud::Tools::Tester::
        TestParameters.new('vcloud_tools_testing_config.yaml')
      vapp_name = "vapp-vcloud-tools-tests-#{Time.now.strftime('%s')}"
      date_metadata = DateTime.parse('2013-10-23 15:34:00 +0000')
      bootstrap_script = File.join(File.dirname(__FILE__),
        "data/basic_preamble_test.erb")
      @test_data = {
        vapp_name: vapp_name,
        vdc_name: parameters.vdc_name,
        catalog: parameters.catalog,
        vapp_template: parameters.catalog_item,
        date_metadata: date_metadata,
        bootstrap_script: bootstrap_script,
        network1: parameters.network1,
        network1_ip: parameters.network1_ip,
        network2: parameters.network2,
        network2_ip: parameters.network2_ip,
        storage_profile: parameters.storage_profile
      }
      @config_yaml = ErbHelper.convert_erb_template_to_yaml(@test_data, File.join(File.dirname(__FILE__), 'data/happy_path.yaml.erb'))
      @fog_interface = Vcloud::Fog::ServiceInterface.new
      Vcloud::Launcher::Launch.new.run(@config_yaml, { "dont-power-on" => true })

      @vapp_query_result = @fog_interface.get_vapp_by_name_and_vdc_name(@test_data[:vapp_name], @test_data[:vdc_name])
      @vapp_id = @vapp_query_result[:href].split('/').last

      @vapp = @fog_interface.get_vapp @vapp_id
      @vm = @vapp[:Children][:Vm].first
      @vm_id = @vm[:href].split('/').last

      @vm_metadata = Vcloud::Core::Vm.get_metadata @vm_id
    end

    context 'provision vapp' do
      it 'should create a vapp' do
        @vapp[:name].should == @test_data[:vapp_name]
        @vapp[:'ovf:NetworkSection'][:'ovf:Network'].count.should == 2
        vapp_networks = @vapp[:'ovf:NetworkSection'][:'ovf:Network'].collect { |connection| connection[:ovf_name] }
        vapp_networks.should =~ [@test_data[:network1], @test_data[:network2]]
      end

      it "should create vm within vapp" do
        @vm.should_not be_nil
      end

    end

    context "customize vm" do
      it "change cpu for given vm" do
        extract_memory(@vm).should == '8192'
        extract_cpu(@vm).should == '4'
      end

      it "should have added the right number of metadata values" do
        @vm_metadata.count.should == 6
      end

      it "the metadata should be equivalent to our input" do
        @vm_metadata[:is_true].should == true
        @vm_metadata[:is_integer].should == -999
        @vm_metadata[:is_string].should == 'Hello World'
      end

      it "should attach extra hard disks to vm" do
        disks = extract_disks(@vm)
        disks.count.should == 3
        [{:name => 'Hard disk 2', :size => '1024'}, {:name => 'Hard disk 3', :size => '2048'}].each do |new_disk|
          disks.should include(new_disk)
        end
      end

      it "should configure the vm network interface" do
        vm_network_connection = @vm[:NetworkConnectionSection][:NetworkConnection]
        vm_network_connection.should_not be_nil
        vm_network_connection.count.should == 2


        primary_nic = vm_network_connection.detect { |connection| connection[:network] == @test_data[:network1] }
        primary_nic[:network].should == @test_data[:network1]
        primary_nic[:NetworkConnectionIndex].should == @vm[:NetworkConnectionSection][:PrimaryNetworkConnectionIndex]
        primary_nic[:IpAddress].should == @test_data[:network1_ip]
        primary_nic[:IpAddressAllocationMode].should == 'MANUAL'

        second_nic = vm_network_connection.detect { |connection| connection[:network] == @test_data[:network2] }
        second_nic[:network].should == @test_data[:network2]
        second_nic[:NetworkConnectionIndex].should == '1'
        second_nic[:IpAddress].should == @test_data[:network2_ip]
        second_nic[:IpAddressAllocationMode].should == 'MANUAL'

      end

      it 'should assign guest customization script to the VM' do
        @vm[:GuestCustomizationSection][:CustomizationScript].should =~ /message: hello world/
        @vm[:GuestCustomizationSection][:ComputerName].should == @test_data[:vapp_name]
      end

      it "should assign storage profile to the VM" do
        @vm[:StorageProfile][:name].should == @test_data[:storage_profile]
      end

    end

    after(:all) do
      unless ENV['VCLOUD_TOOLS_RSPEC_NO_DELETE_VAPP']
        File.delete @config_yaml
        @fog_interface.delete_vapp(@vapp_id).should == true
      end
    end

  end

  def extract_memory(vm)
    vm[:'ovf:VirtualHardwareSection'][:'ovf:Item'].detect { |i| i[:'rasd:ResourceType'] == '4' }[:'rasd:VirtualQuantity']
  end

  def extract_cpu(vm)
    vm[:'ovf:VirtualHardwareSection'][:'ovf:Item'].detect { |i| i[:'rasd:ResourceType'] == '3' }[:'rasd:VirtualQuantity']
  end

  def extract_disks(vm)
    vm[:'ovf:VirtualHardwareSection'][:'ovf:Item'].collect { |d|
      {:name => d[:"rasd:ElementName"], :size => (d[:"rasd:HostResource"][:ns12_capacity] || d[:"rasd:HostResource"][:vcloud_capacity])} if d[:'rasd:ResourceType'] == '17'
    }.compact
  end

end
