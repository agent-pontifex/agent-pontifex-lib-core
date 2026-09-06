-module(gleam@time@calendar).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([local_offset/0, month_to_string/1, month_to_int/1, month_from_int/1, is_leap_year/1, is_valid_date/1, is_valid_time_of_day/1, naive_date_compare/2]).
-export_type([date/0, time_of_day/0, month/0]).
-moduledoc(~" This module is for working with the Gregorian calendar, established by
 Pope Gregory XIII in 1582!

 ## When should you use this module?

 > **tldr:** You probably want to use [`gleam/time/timestamp`](./timestamp.html)
 > instead!

 Calendar time is difficult to work with programmatically, it is the source
 of most time-related bugs in software. Compared to _epoch time_, which the
 `gleam/time/timestamp` module uses, there are many disadvantages to
 calendar time:

 - They are ambiguous if you don't know what time-zone is being used.

 - A time-zone database is required to understand calendar time even when
   you have the time zone. These are large and your program has to
   continously be updated as new versions of the database are published.

 - The type permits invalid states. e.g. `days` could be set to the number
   32, but this should not be possible!

 - There is not a single unique canonical value for each point in time,
   thanks to time zones. Two different `Date` + `TimeOfDay` value pairs
   could represent the same point in time. This means that you can't check
   for time equality with `==` when using calendar types.

 - They are computationally complex, using a more memory to represent and
   requiring a lot more CPU time to manipulate.

 There are also advantages to calendar time:

 - Calendar time is how human's talk about time, so if you want to show a
   time or take a time from a human user then calendar time will make it
   easier for them.

 - They can represent more abstract time periods such as \"New Year's Day\".
   This may seem like an exact window of time at first, but really the
   definition of \"New Year's Day\" is more fuzzy than that. When it starts
   and ends will depend where in the world you are, so if you want to refer
   to a day as a global concept instead of a fixed window of time for that
   day in a specific location, then calendar time can represent that.

 So when should you use calendar time? These are our recommendations:

 - Default to `gleam/time/timestamp`, which is epoch time. It is
   unambiguous, efficient, and significantly less likely to result in logic
   bugs.

 - When writing time to a database or other data storage use epoch time,
   using whatever epoch format it supports. For example, PostgreSQL
   `timestamp` and `timestampz` are both epoch time, and `timestamp` is
   preferred as it is more straightforward to use as your application is
   also using epoch time.

 - When communicating with other computer systems continue to use epoch
   time. For example, when sending times to another program you could
   encode time as UNIX timestamps (seconds since 00:00:00 UTC on 1 January
   1970).

 - When communicating with humans use epoch time internally, and convert
   to-and-from calendar time at the last moment, when iteracting with the
   human user. It may also help the users to also show the time as a fuzzy
   duration from the present time, such as \"about 4 days ago\".

 - When representing \"fuzzy\" human time concepts that don't exact periods
   in time, such as \"one month\" (varies depending on which month, which
   year, and in which time zone) and \"Christmas Day\" (varies depending on
   which year and time zone) then use calendar time.

 Any time you do use calendar time you should be extra careful! It is very
 easy to make mistake with. Avoid it where possible.

 ## Time zone offsets

 This package includes the `utc_offset` value and the `local_offset`
 function, which are the offset for the UTC time zone and get the time
 offset the computer running the program is configured to respectively.

 If you need to use other offsets in your program then you will need to get
 them from somewhere else, such as from a package which loads the
 [IANA Time Zone Database](https://www.iana.org/time-zones), or from the
 website visitor's web browser, which your frontend can send for you.

 ## Use in APIs

 If you are making an API such as a HTTP JSON API you are encouraged to use
 Unix timestamps instead of calendar times.").

-type date() :: {date, integer(), month(), integer()}.

-type time_of_day() :: {time_of_day, integer(), integer(), integer(), integer()}.

-type month() :: january | february | march | april | may | june | july | august | september | october | november | december.

-file("src/gleam/time/calendar.gleam", 147).
-spec local_offset() -> gleam@time@duration:duration().
-doc(~" Get the offset for the computer's currently configured time zone.

 Note this may not be the time zone that is correct to use for your user.
 For example, if you are making a web application that runs on a server you
 want _their_ computer's time zone, not yours.

 This is the _current local_ offset, not the current local time zone. This
 means that while it will result in the expected outcome for the current
 time, it may result in unexpected output if used with other timestamps. For
 example: a timestamp that would locally be during daylight savings time if
 is it not currently daylight savings time when this function is called.
").
local_offset() ->
    gleam@time@duration:seconds(gleam_time_ffi:local_time_offset_seconds()).

-file("src/gleam/time/calendar.gleam", 163).
-spec month_to_string(month()) -> binary().
-doc(~" Returns the English name for a month.

 # Examples

 ```gleam
 month_to_string(April)
 // -> \"April\"
 ```").
month_to_string(Month) ->
    case Month of
        january ->
            ~"January";

        february ->
            ~"February";

        march ->
            ~"March";

        april ->
            ~"April";

        may ->
            ~"May";

        june ->
            ~"June";

        july ->
            ~"July";

        august ->
            ~"August";

        september ->
            ~"September";

        october ->
            ~"October";

        november ->
            ~"November";

        december ->
            ~"December"
    end.

-file("src/gleam/time/calendar.gleam", 188).
-spec month_to_int(month()) -> integer().
-doc(~" Returns the number for the month, where January is 1 and December is 12.

 # Examples

 ```gleam
 month_to_int(January)
 // -> 1
 ```").
month_to_int(Month) ->
    case Month of
        january ->
            1;

        february ->
            2;

        march ->
            3;

        april ->
            4;

        may ->
            5;

        june ->
            6;

        july ->
            7;

        august ->
            8;

        september ->
            9;

        october ->
            10;

        november ->
            11;

        december ->
            12
    end.

-file("src/gleam/time/calendar.gleam", 213).
-spec month_from_int(integer()) -> {ok, month()} | {error, nil}.
-doc(~" Returns the month for a given number, where January is 1 and December is 12.

 # Examples

 ```gleam
 month_from_int(1)
 // -> Ok(January)
 ```").
month_from_int(Month) ->
    case Month of
        1 ->
            {ok, january};

        2 ->
            {ok, february};

        3 ->
            {ok, march};

        4 ->
            {ok, april};

        5 ->
            {ok, may};

        6 ->
            {ok, june};

        7 ->
            {ok, july};

        8 ->
            {ok, august};

        9 ->
            {ok, september};

        10 ->
            {ok, october};

        11 ->
            {ok, november};

        12 ->
            {ok, december};

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/calendar.gleam", 290).
-spec is_leap_year(integer()) -> boolean().
-doc(~" Determines if a given year is a leap year.

 A leap year occurs every 4 years, except for years divisible by 100,
 unless they are also divisible by 400.

 # Examples

 ```gleam
 is_leap_year(2024)
 // -> True
 ```

 ```gleam
 is_leap_year(2023)
 // -> False
 ```
").
is_leap_year(Year) ->
    case (Year rem 400) =:= 0 of
        true ->
            true;

        false ->
            case (Year rem 100) =:= 0 of
                true ->
                    false;

                false ->
                    (Year rem 4) =:= 0
            end
    end.

-file("src/gleam/time/calendar.gleam", 254).
-spec is_valid_date(date()) -> boolean().
-doc(~" Checks if a given date is valid.

 This function properly accounts for leap years when validating February days.
 A leap year occurs every 4 years, except for years divisible by 100,
 unless they are also divisible by 400.

 # Examples

 ```gleam
 is_valid_date(Date(2023, April, 15))
 // -> True
 ```

 ```gleam
 is_valid_date(Date(2023, April, 31))
 // -> False
 ```

 ```gleam
 is_valid_date(Date(2024, February, 29))
 // -> True (2024 is a leap year)
 ```
").
is_valid_date(Date) ->
    {date, Year, Month, Day} = Date,
    case Day < 1 of
        true ->
            false;

        false ->
            case Month of
                january ->
                    Day =< 31;

                march ->
                    Day =< 31;

                may ->
                    Day =< 31;

                july ->
                    Day =< 31;

                august ->
                    Day =< 31;

                october ->
                    Day =< 31;

                december ->
                    Day =< 31;

                april ->
                    Day =< 30;

                june ->
                    Day =< 30;

                september ->
                    Day =< 30;

                november ->
                    Day =< 30;

                february ->
                    Max_february_days = case is_leap_year(Year) of
                        true ->
                            29;

                        false ->
                            28
                    end,
                    Day =< Max_february_days
            end
    end.

-file("src/gleam/time/calendar.gleam", 313).
-spec is_valid_time_of_day(time_of_day()) -> boolean().
-doc(~" Checks if a time of day is valid.

 Validates that hours are 0-23, minutes are 0-59, seconds are 0-59,
 and nanoseconds are 0-999,999,999.

 # Examples

 ```gleam
 is_valid_time_of_day(TimeOfDay(12, 30, 45, 123456789))
 // -> True
 ```
").
is_valid_time_of_day(Time) ->
    {time_of_day, Hours, Minutes, Seconds, Nanoseconds} = Time,
    (((((((Hours >= 0) andalso (Hours =< 23)) andalso (Minutes >= 0)) andalso (Minutes =< 59)) andalso (Seconds >= 0)) andalso (Seconds =< 59)) andalso (Nanoseconds >= 0)) andalso (Nanoseconds =< 999999999).

-file("src/gleam/time/calendar.gleam", 340).
-spec naive_date_compare(date(), date()) -> gleam@order:order().
-doc(~" Naively compares two dates without any time zone information, returning an
 order.

 ## Correctness

 This function compares dates without any time zone information, only using
 the rules for the gregorian calendar. This is typically sufficient, but be
 aware that in reality some time zones will change their calendar date
 occasionally. This can result in days being skipped, out of order, or
 happening multiple times.

 If you need real-world correct time ordering then use the
 `gleam/time/timestamp` module instead.
").
naive_date_compare(One, Other) ->
    _pipe = gleam@int:compare(erlang:element(2, One), erlang:element(2, Other)),
    _pipe@1 = gleam@order:lazy_break_tie(_pipe, fun() ->
        gleam@int:compare(month_to_int(erlang:element(3, One)), month_to_int(erlang:element(3, Other)))
    end),
    gleam@order:lazy_break_tie(_pipe@1, fun() ->
        gleam@int:compare(erlang:element(4, One), erlang:element(4, Other))
    end).

