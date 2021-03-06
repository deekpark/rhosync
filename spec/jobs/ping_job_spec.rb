require File.join(File.dirname(__FILE__),'..','spec_helper')

describe "PingJob" do
  it_should_behave_like "SpecBootstrapHelper"
  it_should_behave_like "SourceAdapterHelper"
  
  before(:each) do
     @u1_fields = {:login => 'testuser1'}
     @u1 = User.create(@u1_fields) 
     @u1.password = 'testpass1'
     @c1_fields = {
       :device_type => 'Apple',
       :device_pin => 'abcde',
       :device_port => '3333',
       :user_id => @u1.id,
       :app_id => @a.id 
     }
     @c1 = Client.create(@c1_fields,{:source_name => @s_fields[:name]})
     @a.users << @u1.id
  end
   
  it "should perform apple ping" do
    params = {"user_id" => @u.id, "api_token" => @api_token,
      "sources" => [@s.name], "message" => 'hello world', 
      "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3', "phone_id" => nil}
    Apple.should_receive(:ping).once.with({'device_pin' => @c.device_pin,
      'device_port' => @c.device_port, 'client_id' => @c.id}.merge!(params))
    PingJob.perform(params)
  end
  
  it "should perform blackberry ping" do
    params = {"user_id" => @u.id, "api_token" => @api_token,
      "sources" => [@s.name], "message" => 'hello world', 
      "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3', "phone_id" => nil}
    @c.device_type = 'blackberry'
    Blackberry.should_receive(:ping).once.with({'device_pin' => @c.device_pin,
      'device_port' => @c.device_port, 'client_id' => @c.id}.merge!(params))
    PingJob.perform(params)
  end
  
  it "should skip ping for empty device_type" do
    params = {"user_id" => @u.id, "api_token" => @api_token,
      "sources" => [@s.name], "message" => 'hello world', 
      "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3'}
    @c.device_type = nil
    PingJob.should_receive(:log).once.with("Skipping ping for non-registered client_id '#{@c.id}'...")
    lambda { PingJob.perform(params) }.should_not raise_error
  end
  
  it "should skip ping for empty device_pin" do
    params = {"user_id" => @u.id, "api_token" => @api_token,
      "sources" => [@s.name], "message" => 'hello world', 
      "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3',"phone_id"=>nil}
    @c.device_type = 'blackberry'
    @c.device_pin = nil
    PingJob.should_receive(:log).once.with("Skipping ping for non-registered client_id '#{@c.id}'...")
    lambda { PingJob.perform(params) }.should_not raise_error
  end

  it "should drop ping if it's already in user's device pin list" do
    params = {"user_id" => @u.id, "api_token" => @api_token,
      "sources" => [@s.name], "message" => 'hello world', 
      "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3', "phone_id"=>nil}

    # another client with the same device pin ...
    @c1 = Client.create(@c_fields,{:source_name => @s_fields[:name]})
    # and yet another one ...
    @c2 = Client.create(@c_fields,{:source_name => @s_fields[:name]})
    
    Rhosync::Apple.stub!(:get_config).and_return({:test => {:iphonecertfile=>"none"}})
    #Apple.should_receive(:ping).with({'device_pin' => @c.device_pin, 'device_port' => @c.device_port, 'client_id' => @c.id}.merge!(params))
    PingJob.should_receive(:log).twice.with(/Dropping ping request for client/)
    lambda { PingJob.perform(params) }.should_not raise_error
  end
  
  it "should drop ping if it's already in user's phone id list and device pin is different" do
    params = {"user_id" => @u.id, "api_token" => @api_token,
      "sources" => [@s.name], "message" => 'hello world', 
      "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3'}
    @c.phone_id = '3'
    @c_fields.merge!(:phone_id => '3')
    # another client with the same phone id..
    @c1 = Client.create(@c_fields,{:source_name => @s_fields[:name]})
    #  yet another...
    @c2 = Client.create(@c_fields,{:source_name => @s_fields[:name]})
    Rhosync::Apple.stub!(:get_config).and_return({:test => {:iphonecertfile=>"none"}})
    #Apple.should_receive(:ping).with({'device_pin' => @c.device_pin, 'phone_id' => @c.phone_id, 'device_port' => @c.device_port, 'client_id' => @c.id}.merge!(params))
    PingJob.should_receive(:log).twice.with(/Dropping ping request for client/)
    lambda { PingJob.perform(params) }.should_not raise_error
  end
  
   it "should process all pings even if some of them are failing" do
      params = {"user_id" => [ @u.id, @u1.id], "api_token" => @api_token,
        "sources" => [@s.name], "message" => 'hello world', 
        "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3', 'phone_id' => nil }
      @c.phone_id = '3'
      
      scrubbed_params = params.dup
      scrubbed_params['vibrate'] = '5'
      @c1.device_type = 'blackberry'
      
      Apple.should_receive(:ping).with(params.merge!({'device_pin' => @c.device_pin, 'phone_id' => @c.phone_id, 'device_port' => @c.device_port,'client_id' => @c.id})).and_return { raise SocketError.new("Socket failure") }
      Blackberry.should_receive(:ping).with({'device_pin' => @c1.device_pin, 'device_port' => @c1.device_port, 'client_id' => @c1.id}.merge!(scrubbed_params))
      exception_raised = false
      begin
        PingJob.perform(params)
      rescue Exception => e
        exception_raised = true
      end
      exception_raised.should == true
    end
  
    it "should skip ping for unknown user or user with no clients" do
      params = {"user_id" => [ 'fake_user' ], "api_token" => @api_token,
        "sources" => [@s.name], "message" => 'hello world', 
        "vibrate" => '5', "badge" => '5', "sound" => 'hello.mp3', 'phone_id' => nil }
      PingJob.should_receive(:log).once.with(/Skipping ping for unknown user 'fake_user' or 'fake_user' has no registered clients.../)
      PingJob.perform(params)
    end
end