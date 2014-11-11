# From https://gist.github.com/pettyjamesm/3746457

require 'monitor'

module StackBuilder::Common

    class Semaphore

        def initialize(maxval = nil)
            maxval = maxval.to_i unless maxval.nil?
            raise ArgumentError.new("Semaphores must use a positive maximum value or have no maximum!") if maxval and maxval <= 0
            @max   = maxval || -1
            @count = 0
            @mon   = Monitor.new
            @dwait = @mon.new_cond
            @uwait = @mon.new_cond
        end

        def count; @mon.synchronize { @count } end

        def up!(number = 1)
            if (number > 1)
                number.times { up!(1) }
                count
            else
                @mon.synchronize do
                    @uwait.wait while @max > 0 and @count == @max
                    @dwait.signal if @count == 0
                    @count += 1
                end
            end
        end

        def down!(number = 1)
            if (number > 1)
                number.times { down!(1) }
                count
            else
                @mon.synchronize do
                    @dwait.wait while @count == 0
                    @uwait.signal if @count == @max
                    @count -= 1
                end
            end
        end

        alias_method :wait, :down!
        alias_method :signal, :up!
    end

end
