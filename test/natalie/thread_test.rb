require_relative '../spec_helper'

$results = []

def create_threads
  1.upto(5).map do |i|
    Thread.new do
      x = "#{i}foo"
      $results << x
      sleep 1
      $results << x + "bar"
    end
  end
end

describe 'Thread' do
  it 'works' do
    threads = create_threads
    1_000_000.times do
      'trigger gc'
    end
    threads.each(&:join)
    $results.size.should == 10
  end

  describe '#join' do
    it 'waits for the thread to finish' do
      start = Time.now
      t = Thread.new { sleep 0.1 }
      t.join
      (Time.now - start).should >= 0.1
    end

    it 'returns the thread' do
      t = Thread.new { 1 }
      t.join.should == t
    end

    it 'can be called multiple times' do
      t = Thread.new { 1 }
      t.join.should == t

      # make sure thread id reuse doesn't cause later join to block
      other_threads = 1.upto(100).map { Thread.new { sleep } }
      sleep 1

      # if the thread id gets reused and we are using pthread_join with that id,
      # then this will block on one of the above threads.
      10.times { t.join.should == t }

      other_threads.each(&:kill)
    end
  end

  describe '#value' do
    it 'returns its value' do
      t = Thread.new { 101 }
      t.join.should == t
      t.value.should == 101
    end

    it 'calls join implicitly' do
      t = Thread.new { sleep 1; 102 }
      t.value.should == 102
    end
  end

  describe 'Fibers within threads' do
    it 'works' do
      t = Thread.new do
        @f = Fiber.new do
          1
        end
        @f.resume.should == 1
      end
      t.join
    end
  end

  describe '.list' do
    it 'keeps a list of all threads' do
      Thread.list.should == [Thread.current]
      t = Thread.new { sleep 0.5 }
      Thread.list.should == [Thread.current, t]
      t.join
      Thread.list.should == [Thread.current]
    end
  end

  describe '#fetch' do
    it 'can be called with a block' do
      Thread.current.fetch(:foo) { 1 + 2 }.should == 3
    end
  end
end