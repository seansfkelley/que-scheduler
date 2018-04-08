require 'spec_helper'
require 'active_support/core_ext/numeric/time'

RSpec.describe Que::Scheduler::EnqueueingCalculator do
  QSSP = described_class

  let(:all_keys) do
    %w[
      HalfHourlyTestJob
      WithArgsTestJob
      daily_test_job_specifying_class
      DailyTestJob
      TwiceDailyTestJob
      TimezoneTestJob
    ]
  end

  it 'should not enqueue anything if not enough time has gone by' do
    run_test('2017-10-08T16:40:32', 1.second, {})
  end

  it 'should enqueue the HalfHourlyTestJob if half an hour has gone by' do
    run_test('2017-10-08T16:40:32', 31.minutes, HalfHourlyTestJob => [{}])
  end

  it 'should enqueue the HalfHourlyTestJob just once if more than an hour has gone by' do
    # Not "every_event", so, we just schedule the latest
    run_test('2017-10-08T16:40:32', 61.minutes, HalfHourlyTestJob => [{}])
  end

  it 'should enqueue if the run time is exactly the cron time' do
    run_test('2017-10-08T16:59:59', 1.seconds, HalfHourlyTestJob => [{}])
  end

  it 'should enqueue if a job has been defined in a different timezone' do
    # Last scheduler run time is 18:04:58 in Finland (+3).
    # This run time is 10:04:59 in New York (-5)
    last_run = Time.zone.parse('2017-12-01T18:04:58+03')
    this_run = Time.zone.parse('2017-12-01T10:04:59-05')
    # Prove this is just one second different
    expect(this_run - last_run).to eq(1.second)

    # The cron was defined for 7:05 in Los Angeles (-8) so should not yet run (1 sec too early).
    run_test_with_times(last_run, this_run, {})

    # Now tip it over the required time by a 1 second so it should run.
    # Since it is an `every_event` job it should receive the schedule time as an arg.
    expected_arg_time = Time.zone.parse('2017-12-01T07:05:00-08')
    run_test_with_times(
      last_run, this_run + 1.second, TimezoneTestJob => [{ args: [expected_arg_time] }]
    )
  end

  # This is testing that the fugit cron "next_time" doesn't return the current time if it matches.
  # It truly is the "next" time.
  it 'should not enqueue if the previous run time was exactly the cron time' do
    run_test('2017-10-08T16:00:00', 1.seconds, {})
  end

  it 'should enqueue jobs with args' do
    run_test(
      '2017-10-08T11:39:59',
      2.seconds,
      WithArgsTestJob => [{ args: ['My Args', 1234, { 'some_hash' => true }] }]
    )
  end

  it 'should enqueue jobs that specify the job class as an arg' do
    run_test(
      '2017-10-08T03:09:59',
      2.seconds,
      SpecifiedByClassTestJob => [{}]
    )
  end

  it 'should enqueue an every_event job once with date arg if seen to be missed once' do
    run_test(
      '2017-10-08T06:09:59',
      2.seconds,
      DailyTestJob => [{ args: [Time.zone.parse('2017-10-08T06:10:00')] }]
    )
  end

  it 'should enqueue an every_event job multiple times if missed repeatedly' do
    run_test(
      '2017-10-08T02:09:59',
      2.days,
      # These are "missable", so only come up once
      HalfHourlyTestJob => [{}],
      WithArgsTestJob => [{ args: ['My Args', 1234, { 'some_hash' => true }] }],
      SpecifiedByClassTestJob => [{}],
      # These are "every_event", so all their missed schedules are enqueued, with that
      # Time as an argument.
      DailyTestJob => [
        { args: [Time.zone.parse('2017-10-08T06:10:00')] },
        { args: [Time.zone.parse('2017-10-09T06:10:00')] }
      ],
      TwiceDailyTestJob => [
        { args: [Time.zone.parse('2017-10-08T11:10:00')], queue: 'backlog', priority: 35 },
        { args: [Time.zone.parse('2017-10-08T16:10:00')], queue: 'backlog', priority: 35 },
        { args: [Time.zone.parse('2017-10-09T11:10:00')], queue: 'backlog', priority: 35 },
        { args: [Time.zone.parse('2017-10-09T16:10:00')], queue: 'backlog', priority: 35 }
      ]
    )
  end

  def run_test(last_run_time, delay_since_last_scheduler, expect_scheduled)
    last_time = Time.zone.parse(last_run_time)
    as_time = last_time + delay_since_last_scheduler
    run_test_with_times(last_time, as_time, expect_scheduled)
  end

  def run_test_with_times(last_time, as_time, expect_scheduled)
    scheduler_job_args = Que::Scheduler::SchedulerJobArgs.new(
      last_run_time: last_time,
      job_dictionary: all_keys,
      as_time: as_time
    )
    out = QSSP.parse(::Que::Scheduler::DefinedJob.defined_jobs, scheduler_job_args)
    exp = Que::Scheduler::EnqueueingCalculator::Result.new(
      missed_jobs: expect_scheduled, schedule_dictionary: all_keys
    )
    expect(out.missed_jobs).to eq(exp.missed_jobs)
    expect(out.schedule_dictionary).to eq(exp.schedule_dictionary)
  end
end