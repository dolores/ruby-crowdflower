$: << File.dirname(__FILE__) + "/../lib"

require 'crowdflower'
require 'json'

API_KEY = YAML::load(File.read("api.yml")) 
#add PN to yml file also 
DOMAIN_BASE = "https://api.crowdflower.com" || "https://api.localdev.crowdflower.com:8443"


unless API_KEY && API_KEY.size > 3
  puts <<EOF

  These integration tests interact with api.crowdflower.com.
  In order to run them, you will need to specify your API key.

  This file is meant only as a reference - please understand
  what you are doing before using the API - you are responsible
  for your usage.

EOF

  exit 1
end

I_AM_RICH = ENV["CF_LIVE_TRANSACTIONS"] == "true"

if I_AM_RICH
  puts "*** LIVE TRANSACTIONS ENABLED - THIS TEST RUN WILL BE CHARGED ***"
end

def wait_until
  10.times do
    if yield
      return
    end
    sleep 5 
  end
  raise "Condition not met in a reasonable time period"
end

def assert(truth)
  unless truth
    raise "Condition not met"
  end
end

def assert_exception_raised expected_exception_class
  begin
    yield
  rescue expected_exception_class
    return
  end
  raise "exception #{expected_exception_class} has not been raised"
end

def say(msg)
  $stdout.puts msg
end

#################################################
# API CONNECTION
#################################################
say "Connecting to the API"
CrowdFlower.connect! API_KEY, DOMAIN_BASE

#################################################
# CREATE JOB
#################################################
say "Creating a blank job."
job_1 = CrowdFlower::Job.create("Job_1: Connection Check")
p "job_1 id: #{job_1.get["id"]}"
p "job_1 units_count: #{job_1.get["units_count"]}"

#################################################
# CHECK/ ENABLE CHANNELS 
################################################# 
say "Checking that job_1 does not have any enabled channels."
assert job_1.channels["enabled_channels"].empty?

say "Enabling the cf_internal channel."
job_1.enable_channels("cf_internal")
assert job_1.channels["enabled_channels"] == ["cf_internal"]

#################################################
# UPLOAD DATA/ CREATE NEW JOB
#################################################
say "Uploading CSV to create job_2."
job_2 = CrowdFlower::Job.upload(File.dirname(__FILE__) + "/crowdshopping.csv", "text/csv")
job_2_id = job_2.get["id"]
p "job_2 id: #{job_2_id}"

#################################################
# ADD UNITS
#################################################
say "-- Waiting for CrowdFlower to process the data."
wait_until { job_2.get["units_count"] == 6 }

say "Adding some more data."
job_2.upload(File.dirname(__FILE__) + "/crowdshopping.csv", "text/csv")

say "-- Waiting for CrowdFlower to process the data."
wait_until { job_2.get["units_count"] == 12 }

#################################################
# PING UNITS
#################################################
say "Pinging job_2 units."
assert job_2.units.ping['count'] == 12
assert job_2.units.ping['done'] == true

#################################################
# COUNT UNITS
#################################################
say "Checking for 12 units in job_2."
assert job_2.units.all.size == 12 

#################################################
# UPDATE JOB_2
#################################################
say "Adding title, project number, instructions, CML"
job_2.update({:title => 'Job_2: CrowdShopping',
            :project_number => 'YOUR_PN',
            :instructions => '<p>There are six questions to this task. In this order, the questions ask if you were able to find a pair of Lita shoes for sale in red glitter, gold glitter, multi glitter, silver glitter, black glitter, or other color of glitter.</p><p>There is a photo of the shoe in correlating color as the question right below the question. It will give you a better idea of what to look for.</p>', 
            :cml => '<cml:radios label="Were you able to find an online retailer selling Jeffery Campbell Lita Booties in {{glitter_color}}?" validates="required" name="color_found" instructions="If you found the shoes we are looking for, click yes to fill in the website url."><p class="shoe-img">Example Photo: <img src="{{image}}" width="100" /></p><cml:radio label="Yes, I found an online retailer selling Lita shoes in {{glitter_color}}." value="yes"></cml:radio><cml:radio label="No, I could not find an online retailer selling Lita shoes in {{glitter_color}}." value="no"></cml:radio></cml:radios><br /><cml:text label="Please enter the name of the online retailer." default="Example: Karmaloop" validates="required" only-if="color_found:[yes]" name="please_enter_the_name_of_the_online_retailer"></cml:text><br /><cml:text label="Please enter the url to the shoes you found." default="Example: www.karmaloop.com/jeffery-campbell-litas-multiglitter" validates="required url" only-if="color_found:[yes]" name="please_enter_the_url_to_the_shoes_you_found"></cml:text>'})

#################################################
# ADD/ UPDATE/ REMOVE TAGS 
#################################################
say "Checking if tags exist."
assert job_2.tags.empty?

say "Adding 'shoes' and 'glitter' to tags."
job_2.add_tags ["shoes", "glitter"]
assert job_2.tags.map{|t| t["name"]}.sort == ["glitter", "shoes"]

say "Removing 'shoes' tag."
job_2.remove_tags ["shoes"]
assert job_2.tags.map{|t| t["name"]} == ["glitter"]

say "Updating tags to 'fashion' 'fun' and 'glitter'."
job_2.update_tags ["fashion", "fun", "glitter"]
assert job_2.tags.map{|t| t["name"]} == ["fashion", "fun", "glitter"]

#################################################
# CHECK JOB_2 CHANNELS 
#################################################
say "Checking that channels are turned on."
assert !job_2.channels["enabled_channels"].empty?
p "job_2 enabled_channels: #{job_2.channels["enabled_channels"]}"

#################################################
# ORDER JOB
#################################################
say "Ordering (launching) job_2 with 12 units."
order = CrowdFlower::Order.new(job_2)
order.debit(12, "channel"=>"cf_internal")
wait_until { job_2.get["state"].casecmp('running') == 0}
assert job_2.channels["enabled_channels"] == ["cf_internal"]

#################################################
# UNIT METHODS * correct spelling error (judgeable not judgable) all states use "judgable" :(
#################################################
say "Setting up units."
unit_1 = job_2.units.all.to_a[0][0]
unit_2 = job_2.units.all.to_a[1][0]

unit = CrowdFlower::Unit.new(job_2)
wait_until { unit.get(unit_1)['state'] == 'judgable' }
p "unit_1 id: #{unit_1}"
wait_until { unit.get(unit_1)['state'] == 'judgable' }
p "unit_2 id: #{unit_2}"

say "Making unit_1 a test question (gold)."
unit.make_gold(unit_1)

say "Copying unit_2."
unit.copy(unit_2, job_2_id, "glitter_color"=>"blue")
assert job_2.get["units_count"] == 13

say "Canceling unit_2."
unit.cancel(unit_2)
assert unit.get(unit_2)['state'] == 'canceled'

#################################################
# PAUSE/ RESUME/ CANCEL JOB
#################################################
say "Pausing job_2."
job_2.pause
assert job_2.get["state"] == "paused"
p "job_2 state: #{job_2.get["state"]}"

say "Resuming job_2."
job_2.resume
assert job_2.get["state"] == "running"
p "job_2 state: #{job_2.get["state"]}"

say "Canceling job_2."
job_2.cancel
assert job_2.get["state"] == "canceled"
p "job_2 state: #{job_2.get["state"]}"

say "Deleting job_1."
job_1.delete 
assert job_1.get["state"] == "unordered"

#################################################
# JOB LEGEND
#################################################
say "Checking job_2 legend."
assert !job_2.legend.empty?

#################################################
# COPY JOB_2
#################################################
say "Copying job_2."
job_3 = job_2.copy(:all_units => true)

say "Updating job_3 title."
job_3.update(:title => 'Job_3: Copy of Job_2')
assert job_3.get["title"] == "Job_3: Copy of Job_2"

say "-- Waiting for CrowdFlower to process the data."
wait_until { job_3.get["units_count"] == 13 }
assert job_3.get["units_count"] == 13

#################################################
# WORKER METHODS - missing assertions
#################################################
say "Worker tests are based on a dummy job and a CrowdFlower employee's worker_id"
job       = CrowdFlower::Job.new(422830)
worker    = CrowdFlower::Worker.new(job) 
worker_id = 23542619

say "Notifying worker."
worker.notify(worker_id, "Testing notify method.")

# Will send a one penny bonus to worker
say "Bonusing a worker."
worker.bonus(worker_id, 1) 

say "Flagging worker from one of my jobs."
worker.flag(worker_id, "Testing flag method.", :persist => false)

say "Flagging worker from all my jobs."
worker.flag(worker_id, "Testing flag method across all jobs.", :persist => true)

say "Deflagging worker."
worker.deflag(worker_id, "Testing deflag method.") 

# Be careful if testing the reject method; cannot be undone
# say "Rejecting worker."
# worker.reject(worker_id)

#################################################
# DOWNLOAD REPORTS - missing assetions
#################################################
# Using the completed job from readme examples. 
job = CrowdFlower::Job.new(418404)

say "Downloading Full CSV"
job.download_csv(:full, "full_report.zip")

say "Downloading Aggregated CSV"
job.download_csv(:aggregated, "agg_report.zip") 

say "Downloading Source CSV"
job.download_csv(:source, "source_report.zip") 

say "Downloading Test Questions CSV"
job.download_csv(:gold_report, "gold_report.zip")  

say "Downloading Worker CSV"
job_2.download_csv(:workset, "workset_report.zip")   

say "Downloading JSON"
job_2.download_csv(:json, "json_report.zip") 

#################################################
# END OF TESTS
#################################################
say ">-< Tests complete. >-<"

#################################################
# COME BACK TO THESE:
#################################################
# MORE UNIT METHODS
  # say "Updating the unit."
  # unit.update(unit_id, "glitter_color"=>"green")
  # say "Spliting the unit on delimeter."
  # unit.split(on, with = " ")
  # say "Requesting more judgments for the unit."
  # unit.request_more_judgments(unit_id, 6)
  # say "Creating a new unit as a test question."
  # unit.create("glitter_color"=>"orange", gold: true) 
  # Does deleting a unit do anything??? Still shows in total unit count, still shows in unit data and state says "canceled"
  # say "Deleting the unit."
  # unit.delete(unit_2)

#################################################
# JUDGMENT METHODS 
#################################################
# judgment = CrowdFlower::Judgment.new(job) 
# judgment.all
# judgment.get(judgment_id)
# judgment.get(1239592918)
# Return every judgment for the given unit
# job.units.judgments(unit_id_number) 
# job.units.judgments(444154130) 

#################################################
# UNUSUAL API_KEY TESTS 
#################################################
# say "defining multiple api keys"
# (job_subclass_with_valid_custom_key = Class.new(CrowdFlower::Job)).connect! API_KEY, DOMAIN_BASE
# (job_subclass_with_invalid_custom_key = Class.new(CrowdFlower::Job)).connect! 'invalid api key', DOMAIN_BASE
# job_subclass_with_no_custom_key = Class.new(CrowdFlower::Job)

# say "no default api key"
# assert_exception_raised(CrowdFlower::UsageError) {CrowdFlower::Job.create("job creation should fail")}
# assert_exception_raised(CrowdFlower::UsageError) {job_subclass_with_no_custom_key.create("job creation should fail")}
# assert_exception_raised(CrowdFlower::APIError) {job_subclass_with_invalid_custom_key.create("job creation should fail")}
# assert job_subclass_with_valid_custom_key.create("should be ok").units.ping['count']

# say "invalid default api key"
# CrowdFlower.connect! "invalid default api key", DOMAIN_BASE
# assert_exception_raised(CrowdFlower::APIError) {CrowdFlower::Job.create("job creation should fail")}
# assert_exception_raised(CrowdFlower::APIError) {job_subclass_with_no_custom_key.create("job creation should fail")}
# assert_exception_raised(CrowdFlower::APIError) {job_subclass_with_invalid_custom_key.create("job creation should fail")}
# assert job_subclass_with_valid_custom_key.create("should be ok").units.ping['count']

#################################################
# API_KEY W/ JOB_SUBCLASS 
#################################################
# say "Connecting to the API"
# CrowdFlower.connect! API_KEY, DOMAIN_BASE
# assert CrowdFlower::Job.create("should be ok").units.ping['count']
# assert job_subclass_with_no_custom_key.create("should be ok").units.ping['count']
# assert job_subclass_with_valid_custom_key.create("should be ok").units.ping['count']
# assert_exception_raised(CrowdFlower::APIError) {job_subclass_with_invalid_custom_key.create("job creation should fail")}
# Add this test to check your URL
#assert CrowdFlower::Base.connection.public_url == "localdev.crowdflower.com:80"
