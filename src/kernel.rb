require 'natalie/inline'

module Kernel
  def <=>(other)
    0 if other.object_id == self.object_id || (!is_a?(Comparable) && self == other)
  end

  def then
    if block_given?
      return yield(self)
    end

    Enumerator.new(1) do |yielder|
      yielder.yield(self)
    end
  end
  alias yield_self then

  def enum_for(method = :each, *args, **kwargs, &block)
    enum =
      Enumerator.new do |yielder|
        the_proc = yielder.to_proc || ->(*i) { yielder.yield(*i) }
        send(method, *args, **kwargs, &the_proc)
      end
    if block_given?
      enum.instance_variable_set(:@size_block, block)
      def enum.size
        @size_block.call
      end
    end
    enum
  end
  alias to_enum enum_for

  def initialize_dup(other)
    initialize_copy(other)
    self
  end
  private :initialize_dup

  def initialize_clone(other, freeze: nil)
    initialize_copy(other)
    self
  end
  private :initialize_clone

  def instance_of?(clazz)
    raise TypeError, 'class or module required' unless clazz.is_a?(Module)

    # We have to use this bind because #self might not respond to #class
    # This can be the case if a BasicObject gets #instance_of? defined via #define_method
    Kernel.instance_method(:class).bind(self).call == clazz
  end

  def rand(*args)
    Random::DEFAULT.rand(*args)
  end

  # NATFIXME: Implement Warning class, check class for severity level
  def warn(*warnings, **)
    warnings.each { |warning| $stderr.puts(warning) }
    nil
  end

  class SprintfFormatter
    def initialize(format_string, arguments)
      @format_string = format_string
      @arguments = arguments
      @arguments_index = 0
      @positional_argument_used = nil
      @unnumbered_argument_used = nil
    end

    attr_reader \
      :format_string,
      :arguments,
      :arguments_index

    def format
      tokens = Parser.new(format_string).tokens

      result = tokens.map do |token|
        case token.type
        when :literal
          token.datum
        when :field
          format_field(token)
        else
          raise "unknown token: #{token.inspect}"
        end
      end.join

      begin
        result = result.encode(format_string.encoding)
      rescue ArgumentError, Encoding::UndefinedConversionError
        # we tried
      end

      if $DEBUG && arguments.any? && !@positional_argument_used
        raise ArgumentError, "too many arguments for format string"
      end

      result
    end

    private

    def format_field(token)
      token.flags.each do |flag|
        case flag
        when :width_given_as_arg
          if token.width_arg_position
            token.width = int_from_arg(get_positional_argument(token.width_arg_position))
          else
            token.width = int_from_arg(next_argument)
          end
          token.width *= -1 if token.flags.include?(:width_negative) && !token.width.negative?
        when :precision_given_as_arg
          if token.precision_arg_position
            token.precision = int_from_arg(get_positional_argument(token.precision_arg_position))
          else
            token.precision = int_from_arg(next_argument)
          end
        end
      end

      val = if token.value_arg_name
              get_named_argument(token.value_arg_name)
            elsif token.value_arg_position
              get_positional_argument(token.value_arg_position)
            else
              next_argument
            end

      val = case token.datum
            when nil
              if token.value_arg_name
                # %{foo} doesn't require a specifier
                val.to_s
              else
                raise ArgumentError, 'malformed format string'
              end
            when 'b'
              format_binary(token, val)
            when 'B'
              format_binary(token, val).upcase
            when 'c'
              format_char(token, val)
            when 'd', 'u', 'i'
              format_integer(token, val)
            when 'e'
              format_float_with_e_notation(token, float_from_arg(val), e: 'e')
            when 'E'
              format_float_with_e_notation(token, float_from_arg(val), e: 'E')
            when 'f'
              format_float(token, float_from_arg(val))
            when 'g'
              format_float_g(token, float_from_arg(val), e: 'e')
            when 'G'
              format_float_g(token, float_from_arg(val), e: 'E')
            when 'o'
              format_octal(token, val)
            when 'p'
              val.inspect
            when 's'
              val.to_s
            when 'x'
              format_hex(token, val)
            when 'X'
              format_hex(token, val).upcase
            else
              raise ArgumentError, "malformed format string - %#{token.datum}"
            end

      pad_value(token, val)
    end

    def float_from_arg(arg)
      f = if arg.is_a?(Float)
            arg
          elsif arg.respond_to?(:to_ary)
            arg.to_ary.first
          else
            Float(arg)
          end
      unless f.is_a?(Float)
        raise TypeError, "no implicit conversion of #{arg.class.name} into Float"
      end
      f
    end

    def int_from_arg(arg)
      int = if arg.is_a?(Integer)
              arg
            elsif arg.respond_to?(:to_int)
              arg.to_int
            end
      unless int.is_a?(Integer)
        raise TypeError, "no implicit conversion of #{arg.class.name} into Integer"
      end
      int
    end

    def pad_value(token, val)
      pad_char = token.flags.include?(:zero_padded) ? '0' : ' '

      while token.width && val.size < token.width
        val = pad_char + val
      end

      if token.width && token.width < 0
        val << pad_char while val.size < token.width.abs
      end

      val
    end

    def arg_to_str(arg, one_char: false)
      s = arg.to_str
      unless s.is_a?(String)
        raise TypeError, "can't convert Object to String (#{arg.class.name}#to_str gives #{s.class.name})"
      end
      if one_char && s.size != 1
        raise ArgumentError, '%c requires a character'
      end
      s
    end

    def arg_to_int(arg)
      i = arg.to_int
      unless i.is_a?(Integer)
        raise TypeError, "can't convert Object to Integer (#{arg.class.name}#to_int gives #{i.class.name})"
      end
      i
    end

    def format_char(token, arg)
      if arg.is_a?(Integer)
        arg.chr(format_string.encoding)
      elsif arg.respond_to?(:to_int)
        arg_to_int(arg).chr(format_string.encoding)
      elsif arg.respond_to?(:to_str)
        arg_to_str(arg, one_char: true)
      else
        raise TypeError, "no implicit conversion of #{arg.class.name} into Integer"
      end
    rescue NoMethodError
      raise unless Kernel.instance_method(:instance_of?).bind(arg).call(BasicObject)
      begin
        i = arg.to_int
        unless i.is_a?(Integer)
          raise TypeError, "can't convert BasicObject to Integer"
        end
        i.chr(format_string.encoding)
      rescue NoMethodError
        begin
          s = arg.to_str
          unless s.is_a?(String)
            raise TypeError, "can't convert BasicObject to String"
          end
          if s.size != 1
            raise ArgumentError, '%c requires a character'
          end
          s
        rescue NoMethodError
          raise TypeError, "no implicit conversion of BasicObject into Integer"
        end
      end
    end

    def format_float(token, f)
      token.precision ||= 6
      sprintf(token.c_printf_format, f).sub(/inf/i, 'Inf').sub(/-?nan/i, 'NaN')
    end

    def format_float_g(token, f, e: 'e')
      token.precision ||= 6
      sprintf(token.c_printf_format, f).sub(/inf/i, 'Inf').sub(/-?nan/i, 'NaN')
    end

    def format_float_with_e_notation(token, f, e: 'e')
      token.precision ||= 6
      sprintf(token.c_printf_format, f).sub(/inf/i, 'Inf').sub(/-?nan/i, 'NaN')
    end

    def format_integer(token, arg)
      format_number(token: token, arg: arg, base: 10, bits_per_char: 4, prefix: '')
    end

    def format_binary(token, arg)
      format_number(token: token, arg: arg, base: 2, bits_per_char: 1, prefix: '0b')
    end

    def format_octal(token, arg)
      format_number(token: token, arg: arg, base: 8, bits_per_char: 3, prefix: '0')
    end

    def format_hex(token, arg)
      format_number(token: token, arg: arg, base: 16, bits_per_char: 4, prefix: '0x')
    end

    def format_number(token:, arg:, base:, bits_per_char:, prefix:)
      i = convert_int(arg)

      sign = ''

      if i.negative?
        if (token.flags & [:space, :plus]).any? || base == 10
          sign = '-'
          value = i.abs.to_s(base)
        else
          dotdot_sign = '..'
          width = (token.precision.to_i - 2) * bits_per_char
          value = twos_complement(arg, base, [width, 0].max)
        end
      else
        if token.flags.include?(:plus)
          sign = '+'
        elsif token.flags.include?(:space)
          sign = ' '
        end
        value = i.abs.to_s(base)
      end

      if !token.flags.include?(:alternate_format) || value == '0'
        prefix = ''
      end

      if token.precision
        needed = token.precision - value.size - (dotdot_sign&.size || 0)
        value = ('0' * ([needed, 0].max)) + value
      end

      build_numeric_value_with_padding(
        token: token,
        sign: sign,
        value: value,
        prefix: prefix,
        dotdot_sign: dotdot_sign
      )
    end

    def build_numeric_value_with_padding(token:, sign:, value:, prefix: nil, dotdot_sign: nil)
      width = token.width
      return "#{sign}#{prefix}#{dotdot_sign}#{value}" unless width

      sign_size = sign&.size || 0
      prefix_size = prefix&.size || 0
      dotdot_sign_size = dotdot_sign&.size || 0

      pad_char = token.flags.include?(:zero_padded) && !width.negative? ? '0' : ' '
      needed = width.abs - sign_size - prefix_size - dotdot_sign_size - value.size
      padding = pad_char * [needed, 0].max

      if width.negative?
        "#{sign}#{prefix}#{value}#{padding}"
      elsif pad_char == '0'
        "#{sign}#{prefix}#{padding}#{value}"
      else
        "#{padding}#{prefix}#{sign}#{value}"
      end
    end

    def twos_complement(num, base, width)
      # See this comment in the Ruby source for how this should work:
      # https://github.com/ruby/ruby/blob/3151d7876fac408ad7060b317ae7798263870daa/sprintf.c#L662-L670
      needed_bits = num.abs.to_s(2).size + 1
      bits = [width.to_i, needed_bits].max
      first_digit = (base - 1).to_s(base)
      result = nil
      loop do
        result = (2**bits - num.abs).to_s(base)
        bits += 1
        if result.start_with?(first_digit)
          break
        end
        raise 'something went wrong' if bits > 128 # arbitrarily chosen upper sanity limit
      end
      if result == first_digit + first_digit
        # ..11 can be represented as just ..1
        first_digit
      else
        result
      end
    end

    __define_method__ :sprintf, [:format, :val], <<-END
      assert(format->is_string());
      assert(val->is_float());
      char buf[100];
      auto fmt = format->as_string()->c_str();
      auto dbl = val->as_float()->to_double();
      if (snprintf(buf, 100, fmt, dbl) > 0) {
          if (isnan(dbl) && strcasestr(buf, "-nan")) {
              // dumb hack to fix -NAN on some systems
              dbl *= -1;
              if (snprintf(buf, 100, fmt, dbl) > 0)
                  return new StringObject { buf };
          } else {
              return new StringObject { buf };
          }
      }
      env->raise("ArgumentError", "could not format value");
    END

    def next_argument
      if arguments_index >= arguments.size
        raise ArgumentError, 'too few arguments'
      end
      if @positional_argument_used
        raise ArgumentError, "unnumbered(#{arguments_index}) mixed with numbered"
      end
      arg = arguments[arguments_index]
      @unnumbered_argument_used = arguments_index
      @arguments_index += 1
      arg
    end

    def get_named_argument(name)
      if arguments.size == 1 && arguments.first.is_a?(Hash)
        arguments.first.fetch(name.to_sym)
      else
        raise ArgumentError, 'one hash required'
      end
    end

    def get_positional_argument(position)
      if position > arguments.size
        raise ArgumentError, 'too few arguments'
      end
      if @unnumbered_argument_used
        raise ArgumentError, "numbered(#{position}) after unnumbered(#{@unnumbered_argument_used})"
      end
      @positional_argument_used = position
      arguments[position - 1]
    end

    def convert_int(i)
      if i.is_a?(Integer)
        i
      elsif i.respond_to?(:to_ary)
        i = i.to_ary.first
        raise ArgumentError unless i.is_a?(Integer)
        i
      else
        Integer(i)
      end
    end

    class Parser
      def initialize(format_string)
        @format_string = format_string
        @index = 0
        @chars = format_string.chars
      end

      attr_reader :format_string, :index, :chars

      STATES_AND_TRANSITIONS = {
        literal: {
          default: :literal,
          on_percent: :field_pending,
        },
        literal_percent: {
          default: :literal,
        },
        field_flag: {
          return: :field_pending,
        },
        field_named_argument_angled: {
          on_greater_than: :field_pending,
          default: :field_named_argument_angled,
        },
        field_named_argument_curly: {
          on_right_curly_brace: :field_named_argument_curly_end,
          default: :field_named_argument_curly,
        },
        field_named_argument_curly_end: {
          default: :literal,
          on_percent: :field_pending,
        },
        field_pending: {
          on_alpha: :field_end,
          on_asterisk: :field_width_from_arg,
          on_minus: :field_width_minus,
          on_less_than: :field_named_argument_angled,
          on_left_curly_brace: :field_named_argument_curly,
          on_newline: :literal_percent,
          on_null_byte: :literal_percent,
          on_number: :field_width_or_positional_arg,
          on_percent: :literal,
          on_period: :field_precision_period,
          on_plus: :field_flag,
          on_pound: :field_flag,
          on_space: :field_flag,
          on_zero: :field_flag,
        },
        field_end: {
          default: :literal,
          on_percent: :field_pending,
        },
        field_precision: {
          on_alpha: :field_end,
          on_number: :field_precision,
          on_zero: :field_precision,
        },
        field_precision_from_arg: {
          on_number: :field_precision_from_positional_arg,
          return: :field_pending,
        },
        field_precision_period: {
          on_number: :field_precision,
          on_zero: :field_precision,
          on_asterisk: :field_precision_from_arg,
        },
        field_precision_from_positional_arg: {
          on_dollar: :field_precision_from_positional_arg_end,
          on_number: :field_precision_from_positional_arg,
          on_zero: :field_precision_from_positional_arg,
          return: :field_pending,
        },
        field_precision_from_positional_arg_end: {
          return: :field_pending,
        },
        field_width_or_positional_arg: {
          on_dollar: :positional_argument_end,
          on_number: :field_width_or_positional_arg,
          on_zero: :field_width_or_positional_arg,
          return: :field_pending,
        },
        field_width_minus: {
          on_number: :field_width_or_positional_arg,
          on_zero: :field_width_or_positional_arg,
          on_asterisk: :field_width_from_arg,
        },
        field_width_from_arg: {
          on_number: :field_width_from_positional_arg,
          return: :field_pending,
        },
        field_width_from_positional_arg: {
          on_dollar: :field_width_from_positional_arg_end,
          on_number: :field_width_from_positional_arg,
          on_zero: :field_width_from_positional_arg,
          return: :field_pending,
        },
        field_width_from_positional_arg_end: {
          return: :field_pending,
        },
        positional_argument_end: {
          return: :field_pending,
        }
      }.freeze

      COMPLETE_STATES = %i[
        field_end
        literal
        literal_percent
        field_named_argument_curly_end
      ].freeze

      class Token
        def initialize(type:, datum:, flags: [], width: nil, width_arg_position: nil, precision: nil, precision_arg_position: nil, value_arg_position: nil, value_arg_name: nil)
          @type = type
          @datum = datum
          @flags = flags
          @width = width
          @width_arg_position = width_arg_position
          @precision = precision
          @precision_arg_position = precision_arg_position
          @value_arg_position = value_arg_position
          @value_arg_name = value_arg_name
        end

        attr_accessor :type, :datum, :flags,
          :width, :width_arg_position,
          :precision, :precision_arg_position,
          :value_arg_position, :value_arg_name

        def c_printf_format
          flag_chars = {
            alternate_format: '#',
            space: ' ',
            plus: '+',
            zero_padded: '0',
          }.select { |k| flags.include?(k) }.values.join
          "%#{flag_chars}#{width}.#{precision}#{datum}"
        end
      end

      def tokens
        state = :literal
        width_or_positional_arg = nil
        width = nil
        width_arg_position = nil
        precision = nil
        precision_arg_position = nil
        value_arg_position = nil
        value_arg_name = nil
        flags = []
        tokens = []

        while index < chars.size
          char = current_char
          transition = case char
                      when '%'
                        :on_percent
                      when "\n"
                        :on_newline
                      when "\0"
                        :on_null_byte
                      when '.'
                        :on_period
                      when '#'
                        :on_pound
                      when '+'
                        :on_plus
                      when '-'
                        :on_minus
                      when '*'
                        :on_asterisk
                      when '0'
                        :on_zero
                      when ' '
                        :on_space
                      when '$'
                        :on_dollar
                      when '<'
                        :on_less_than
                      when '>'
                        :on_greater_than
                      when '{'
                        :on_left_curly_brace
                      when '}'
                        :on_right_curly_brace
                      when '1'..'9'
                        :on_number
                      when 'a'..'z', 'A'..'Z'
                        :on_alpha
                      end

          new_state = STATES_AND_TRANSITIONS.dig(state, transition) ||
            STATES_AND_TRANSITIONS.dig(state, :default)

          if !new_state && (return_state = STATES_AND_TRANSITIONS.dig(state, :return))
            # :return is a special transition that consumes no characters
            new_state = return_state
          end

          #puts "#{state.inspect}, given #{char.inspect}, " \
              #"transition #{transition.inspect} to #{new_state.inspect}"

          unless new_state
            raise ArgumentError, "no transition from #{state.inspect} with char #{char.inspect}"
          end

          state = new_state
          next_char unless return_state
          return_state = nil

          case state
          when :literal
            tokens << Token.new(type: :literal, datum: char)
          when :literal_percent
            tokens << Token.new(type: :literal, datum: "%#{char}")
          when :field_pending, :field_precision_period
            :noop
          when :field_flag
            flags << case char
                    when '#'
                      :alternate_format
                    when ' '
                      :space
                    when '+'
                      :plus
                    when '0'
                      :zero_padded
                    else
                      raise ArgumentError, "unknown flag: #{char.inspect}"
                    end
          when :field_width_or_positional_arg
            width_or_positional_arg = (width_or_positional_arg || 0) * 10 + char.to_i
          when :field_width_minus
            flags << :width_negative
          when :field_width_from_arg
            raise ArgumentError, 'width given twice' if width_or_positional_arg || flags.include?(:width_given_as_arg)
            flags << :width_given_as_arg
          when :field_width_from_positional_arg
            width_arg_position = (width_arg_position || 0) * 10 + char.to_i
          when :field_width_from_positional_arg_end
            :noop
          when :field_precision
            raise ArgumentError, 'precision given twice' if flags.include?(:precision_given_as_arg)
            precision = (precision || 0) * 10 + char.to_i
            raise ArgumentError, 'precision too big' if precision > 2**64
          when :field_precision_from_arg
            raise ArgumentError, 'precision given twice' if precision || flags.include?(:precision_given_as_arg)
            flags << :precision_given_as_arg
          when :field_precision_from_positional_arg
            precision_arg_position = (precision_arg_position || 0) * 10 + char.to_i
          when :field_precision_from_positional_arg_end
            :noop
          when :field_named_argument_angled, :field_named_argument_curly
            if value_arg_name
              value_arg_name << char
            else
              value_arg_name = ''
            end
          when :field_named_argument_curly_end
            tokens << Token.new(
              type: :field,
              datum: nil,
              value_arg_name: value_arg_name,
            )
            value_arg_name = nil
          when :field_end
            if width_or_positional_arg
              width = if flags.include?(:width_negative)
                        -width_or_positional_arg
                      else
                        width_or_positional_arg
                      end
            end
            tokens << Token.new(
              type: :field,
              datum: char,
              flags: flags.dup,
              width: width,
              width_arg_position: width_arg_position,
              precision: precision,
              precision_arg_position: precision_arg_position,
              value_arg_position: value_arg_position,
              value_arg_name: value_arg_name,
            )
            width = nil
            width_arg_position = nil
            width_or_positional_arg = nil
            precision = nil
            precision_arg_position = nil
            value_arg_position = nil
            value_arg_name = nil
          when :positional_argument_end
            new_arg_position = width_or_positional_arg
            width_or_positional_arg = nil
            if value_arg_position
              raise ArgumentError, "value given twice - #{new_arg_position}$"
            end
            value_arg_position = new_arg_position
          else
            raise ArgumentError, "unknown state: #{state.inspect}"
          end
        end

        # An incomplete field with no type and having a positional argument
        # produces a literal '%'.
        if state == :positional_argument_end
          tokens << Token.new(type: :literal, datum: '%')
          state = :field_end
        end

        unless COMPLETE_STATES.include?(state)
          raise ArgumentError, "malformed format string #{state}"
        end

        tokens
      end

      private

      def current_char
        chars[index]
      end

      def next_char
        @index += 1
        chars[index]
      end
    end
  end

  def sprintf(format_string, *arguments)
    SprintfFormatter.new(format_string, arguments).format
  end

  # NATFIXME: the ... syntax doesnt appear to pass the block
  def open(*a, **kw, &blk)
    File.open(*a, **kw, &blk)
  end

  alias format sprintf

  def printf(*args)
    if args[0].is_a?(String)
      print(sprintf(*args))
    else
      args[0].write(sprintf(*args[1..]))
    end
  end
end
