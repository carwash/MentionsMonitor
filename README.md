# MentionsMonitor

*A simple Twitter bot that scans for misdirected mentions and blocks the unwitting users.*

## Configuration

Copy `oauth.yaml.example` to `oauth.yaml` and edit it to add your consumer key and secret. The script will prompt you to authorise the first time it is run to add an access token and secret.

## About

MentionsMonitor makes my Twitter mentions page a bit more readable by scanning tweets @-mentioning me and automatically blocking users who appear to have done so by mistake. Having the username [@carwash](https://twitter.com/carwash) means I get a lot of misdirected @-mentions from people – usually people cleaning their automobiles – who don't realise that '@' has special meaning on Twitter. I'm not alone in having this problem: [@sil](https://twitter.com/carwash) has [written](http://www.kryogenix.org/days/2012/06/29/put-the-chocolate-on-the-moose/) about this before; [@denny](https://twitter.com/denny) is [similarly affected](http://denny.me/blockbot/reason.html#all), albeit for different reasons; and [@tomgoskar](https://twitter.com/tomgoskar) had to change his handle from @tag because of it. Like both [@sil](https://twitter.com/carwash) and [@denny](https://twitter.com/denny), an unusually large number of my misdirected mentions seem to come from Indonesia for some reason (with Dutch speakers coming in second – perhaps it's a colonial thing?).

MentionsMonitor was inspired by [@DennysBlockBot](https://twitter.com/DennysBlockBot), [MentionsManager](https://github.com/denny/MentionsManager) but differs from it in a few ways:

- While MentionsManager is designed to be executed periodically, checking all new mentions since the last time it was run, MentionsMonitor is intended to be run continuously in the background, using Twitter's streaming API to vet mentions as they appear and block the originating users in real time;
- Rather than caching a list of all friends and followers (which are subject to change) MentionsMonitor checks the following/follower status of each mentioning user as necessary;
- MentionsMonitor does not send an email notification when it blocks someone. (If I wanted to be notified of every accidental mention, I wouldn't need this script, would I? 😉) Instead, it logs each block to a file as a timestamped MarkDown list, with the name of the blocked user and the tweet that triggered the block;
- The block rules are quite a bit more lax. The sorts of erroneous mentions I get are pretty varied which makes them hard to match programatically, so the block rules look for a few dead giveaways to catch the most obvious culprits, but otherwise err on the side false negatives;
- As a result, there is no separate Twitter account for the bot to inform the user that they've been blocked and explain why. I anticipate almost no false positives, and can reverse any that may occur from the logs.

With the exception of some @carwash-specific block rules the script is not hardcoded to any particular account, so you should just be able to specify any user in the `oauth.yaml` config file and expect it to work.
