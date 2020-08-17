# frozen_string_literal: true

require 'redis'
require 'securerandom'

conn = Redis.new

def new_id
  SecureRandom.uuid
end

def truncate(time)
  Time.new(time.year, time.month, time.day, 0, 0, 0, 0).to_i
end

def random_amount
  rand(100..1000)
end

# RecognitionInfo holds info about app and user.
class RecognitionInfo
  attr_accessor :id, :time, :amount, :user_id, :app_id, :document_id, :document_type, :verified

  def initialize(time = Time.now, app_id = new_id, doc_type = 'Passport', verified = false)
    @id = new_id
    @time = time
    @amount = random_amount
    @user_id = new_id
    @app_id = app_id
    @document_id = new_id
    @document_type = doc_type
    @verified = verified
  end

  def to_s
    "id: #{id}\ttime: #{time}\tamount: #{amount}\tverified: #{verified}\tapp_id: #{app_id}\ttype: #{document_type}"
  end
end

# RecognitionDay holds day stats.
class RecognitionDay
  attr_accessor :time, :amount, :success, :failed, :app_id, :document_type

  def to_s
    "day: #{Time.at(time.to_i).strftime('%Y-%m-%d')}\ttime: #{time}\tamount: #{amount}\tsuccess: #{success}\tfailed: #{failed}"
  end
end

def save_recognition(conn, owner_id, info)
  conn.hmset("recognition:#{info.id}",
             'time', info.time.to_i,
             'amount', info.amount,
             'user_id', info.user_id,
             'app_id', info.app_id,
             'document_id', info.document_id,
             'document_type', info.document_type,
             'verified', info.verified)
  conn.zadd("user:#{owner_id}:recognitions", info.time.to_i, info.id)

  save_recognition_day(conn, owner_id, info)
end

def save_recognition_day(conn, owner_id, info)
  day = truncate info.time
  key = "user:#{owner_id}:recognitions:day:#{day}"

  conn.hset(key, 'time', day)
  conn.hincrby(key, 'amount', info.amount)
  if info.verified
    conn.hincrby(key, 'success', 1)
  else
    conn.hincrby(key, 'failed', 1)
  end

  conn.zadd("user:#{owner_id}:recognitions:days", day, day, nx: true)
end

def load_recognition(conn, id)
  data = conn.hgetall("recognition:#{id}")
  info = RecognitionInfo.new
  info.id = data['id']
  info.time = data['time']
  info.amount = data['amount']
  info.user_id = data['user_id']
  info.app_id = data['app_id']
  info.document_id = data['document_id']
  info.document_type = data['document_type']
  info.verified = data['verified']
  info
end

def load_recognition_day(conn, owner_id, id)
  data = conn.hgetall("user:#{owner_id}:recognitions:day:#{id}")
  day = RecognitionDay.new
  day.time = data['time']
  day.amount = data['amount']
  day.success = data['success']
  day.failed = data['failed']
  day
end

def list_recognitions(conn, owner_id)
  infos = []
  conn.zrange("user:#{owner_id}:recognitions", 0, -1).each do |id|
    info = load_recognition conn, id
    infos << info
  end
  infos
end

def list_recognition_days(conn, owner_id)
  days = []
  conn.zrange("user:#{owner_id}:recognitions:days", 0, -1).each do |id|
    day = load_recognition_day conn, owner_id, id
    days << day
  end
  days
end

owner_id = new_id
app_id = new_id
second_app_id = new_id

test_cases = [
  RecognitionInfo.new(Time.utc(2020, 8, 17, 1, 0, 0), app_id, 'Passport', false),
  RecognitionInfo.new(Time.utc(2020, 8, 18, 1, 0, 0), app_id, 'IdCard', true),
  RecognitionInfo.new(Time.utc(2020, 8, 18, 1, 0, 0), app_id, 'DriverLicense', false),
  RecognitionInfo.new(Time.utc(2020, 8, 19, 1, 0, 0), app_id, 'ProofOfAddress', true),

  RecognitionInfo.new(Time.utc(2020, 8, 17, 1, 0, 0), second_app_id, 'Passport', false),
  RecognitionInfo.new(Time.utc(2020, 8, 17, 1, 0, 0), second_app_id, 'IdCard', true),
  RecognitionInfo.new(Time.utc(2020, 8, 18, 1, 0, 0), second_app_id, 'DriverLicense', false),
  RecognitionInfo.new(Time.utc(2020, 8, 18, 1, 0, 0), second_app_id, 'ProofOfAddress', true)
]

test_cases.each do |info|
  save_recognition conn, owner_id, info
end

recognitions = list_recognitions conn, owner_id
puts "Number of recognitions: #{recognitions.length}"
recognitions.each do |info|
  puts info
end

days = list_recognition_days conn, owner_id
puts "Number of recognitions days: #{days.length}"
days.each do |day|
  puts day
end
