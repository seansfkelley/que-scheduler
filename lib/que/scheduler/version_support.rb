require "que"

# The purpose of this module is to centralise the differences when supporting both que 0.x and
# 1.x with the same gem.
module Que
  module Scheduler
    module VersionSupport
      RETRY_PROC = proc { |count|
        # Maximum one hour, otherwise use the default backoff
        count > 7 ? (60 * 60) : ((count**4) + 3)
      }

      class << self
        # Ensure que-scheduler runs at the highest priority. This is because its priority is a
        # the top of all jobs it enqueues.
        def set_priority(context, priority)
          if zero_major?
            context.instance_variable_set("@priority", priority)
          else
            context.priority = priority
          end
        end

        # Ensure the job runs at least once an hour when it is backing off due to errors
        def apply_retry_semantics(context)
          if zero_major?
            context.instance_variable_set("@retry_interval", RETRY_PROC)
          else
            context.maximum_retry_count = 1 << 128 # Heat death of universe
            context.retry_interval = RETRY_PROC
          end
        end

        def job_attributes(enqueued_job)
          if zero_major?
            enqueued_job.attrs.to_h.transform_keys(&:to_sym)
          else
            enqueued_job.que_attrs.to_h.transform_keys(&:to_sym).tap do |hash|
              hash[:job_id] = hash.delete(:id)
            end
          end
        end

        # Between Que 0.x and 1.x the result of Que execute changed keys from strings to symbols.
        # Here we wrap the concept and make sure either way produces symbols
        def execute(str, args = [])
          normalise_array_of_hashes(Que.execute(str, args))
        end

        def default_scheduler_queue
          zero_major? ? "" : Que::DEFAULT_QUEUE
        end

        def running_synchronously?
          zero_major? ? (Que.mode == :sync) : Que.run_synchronously
        end

        def running_synchronously_code?
          zero_major? ? "Que.mode == :sync" : "Que.run_synchronously = true"
        end

        def zero_major?
          # This is the only way to handle beta releases too
          @zero_major ||= Gem.loaded_specs["que"].version.to_s.split(".").first.to_i.zero?
        end

        private

        def normalise_array_of_hashes(array)
          array.map { |row| row.to_h.transform_keys(&:to_sym) }
        end
      end
    end
  end
end
