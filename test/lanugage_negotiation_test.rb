require 'test_helper'

class ActionController::AbstractRequest
  def self.acceptable_languages=(v)
    @acceptable_languages = v
  end
  attr :cookies, true
  attr :env, true
end

class LanugageNegotiationTest < ActiveSupport::TestCase

  test "ActionController_AbstractRequest_acceptable_language?" do
 
    ar = ActionController::AbstractRequest
 
    ar.acceptable_languages= :ja, :en, :fr
 
    assert ar.acceptable_language? :ja
    assert ar.acceptable_language? :en
    assert ar.acceptable_language? :fr
 
    assert ! ar.acceptable_language?(:de)
    assert ! ar.acceptable_language?(:es)
 
    assert ar.acceptable_language? "fr"
    assert ! ar.acceptable_language?("de")
  end
 

  test "ActionController_AbstractRequest_accepts_languages!" do
 
    ar= ActionController::AbstractRequest
 
    req = ar.new
    ar.acceptable_languages= :ja, :en, :fr
    req.cookies = {}
    req.env = {}
 
    # server default
    assert_equal [ :ja, :en, :fr ], req.accepts_languages!
 
    # ignore invalid specifications
    req.cookies = { 'rails_language' => ['xx'] }
    req.env = { 'HTTP_ACCEPT_LANGUAGE' => 'es, de' }
    assert_equal [ :ja, :en, :fr ], req.accepts_languages!
    
    # Accept-Language
    req.env = { 'HTTP_ACCEPT_LANGUAGE' => 'en-us, fr, en, ja' }
    assert_equal [ :en, :fr, :ja ], req.accepts_languages!
 
    req.env = { 'HTTP_ACCEPT_LANGUAGE' => 'en-us;q=0.8, fr;q=0.1, en, ja' }
    assert_equal [ :en, :fr, :ja ], req.accepts_languages!
 
    # cookie
    req.cookies = { 'rails_language' => ['ja'] }
    assert_equal [ :ja, :en, :fr ], req.accepts_languages!
 
    req.cookies = { 'rails_language' => ['fr'] }
    assert_equal [ :fr, :en, :ja ], req.accepts_languages!
 
    req.env = {}
    assert_equal [ :fr, :ja, :en ], req.accepts_languages!
 
    # arg
    assert_equal [ :ja, :fr, :en ], req.accepts_languages!('ja')
 
    assert_equal [ :en, :fr, :ja ], req.accepts_languages!('en')
 
    assert_equal [ :fr, :ja, :en ], req.accepts_languages!('fr')
 
  end
  
  class MemoizedTestClass
    extend ActiveSupport::Memoizable
    def count
      @count
    end
    def calc(v)
      @count= ( @count || 0 ) + 1
      v
    end
    memoize :calc
  end
 
  test "memoize" do
    mt= MemoizedTestClass.new
    mt.calc(1)
    mt.calc(2)
    mt.calc(1)
    mt.calc(3)
    mt.calc(1)
    assert_equal 3, mt.count
    mt.calc(1)
    mt.calc(2)
    mt.calc(3)
    assert_equal 3, mt.count
    mt.calc(4)
    assert_equal 4, mt.count
    assert MemoizedTestClass.memoized?(:calc)
    MemoizedTestClass.unmemoize :calc
    assert !MemoizedTestClass.memoized?(:calc)
    assert_equal 4, mt.count
    mt.calc(1)
    mt.calc(2)
    mt.calc(3)
    mt.calc(4)
    assert_equal 8, mt.count
    MemoizedTestClass.memoize :calc
    mt.calc(1)
    mt.calc(2)
    mt.calc(3)
    assert_equal 8, mt.count
  end

end
