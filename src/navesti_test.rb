require_relative 'navesti'

# Define a super simple workflow
Navesti.define :test_workflow do
  workflow do
    step "step1" do |data|
      puts "Inside step1"
      data[:step1_completed] = true
      data
    end
    
    step "step2" do |data|
      puts "Inside step2"
      data[:step2_completed] = true
      data
    end
  end
end

# Run it
puts "Before Navesti.run"
result = Navesti.run(:test_workflow, {test: true})
puts "After Navesti.run"
puts "Result: #{result.inspect}" 