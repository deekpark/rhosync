require File.join(File.dirname(__FILE__),'perf_spec_helper')

describe "BulkData Performance" do
  it_should_behave_like "SourceAdapterHelper"
  it_should_behave_like "PerfSpecHelper"
  
  before(:each) do
    basedir = File.join(File.dirname(__FILE__),'..','apps','rhotestapp')
    Rhosync.bootstrap(basedir) do |rhosync|
      rhosync.vendor_directory = File.join(basedir,'..','vendor')
    end
  end
  
  after(:each) do
    delete_data_directory
  end
  
  it "should generate sqlite bulk data for 1000 objects (6000 attributes)" do
    start = start_timer
    @data = get_test_data(1000)
    start = lap_timer('generate data',start)
    set_state('test_db_storage' => @data)
    start = lap_timer('set_state masterdoc',start)
    data = BulkData.create(:name => bulk_data_docname(@a.id,@u.id),
      :state => :inprogress,
      :app_id => @a.id,
      :user_id => @u.id,
      :sources => [@s_fields[:name]])
    BulkDataJob.perform("data_name" => data.name)
    BulkDataJob.after_perform_x("data_name" => data.name)
    lap_timer('BulkDataJob.perform duration',start)
  end
end