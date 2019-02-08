# tweetsearch
Find tweets twitter search won't return 

### Note
- This is an exhaustive search and so is ***extremely*** **time intensive**. 
- Don't expect quick results but do expect thorough results. 
- If the tweet exists, this ***will*** find it.

Based on a twitter-backup script written by JWZ - https://www.jwz.org/hacks/twit-backup.pl

and released snowflake (tweet id) generator code from twitter translated from scala to perl
https://github.com/twitter/snowflake/tree/snowflake-2010

Requires the following perl modules and a twitter API enabled account:
```perl
Net::Twitter
Data::Dumper
Math::BigInt
```

This script as written was mainly used here:
https://www.reddit.com/r/UnfavorableSemicircle/comments/6j2d54/clawing_back_missing_data_from_twitter/

