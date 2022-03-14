Shows various system health metrics. There isn't any one right number for most of these metrics, but look for sudden changes. 

If you have enabled the Twillio webhook, you will see the SMS error rate, which should be low, not much above 10%. 

The publish failure rate is the percentages of tokens claimed that do not result in keys being published. Typically after a token is claimed the keys are published. Althought these are two seperate interactions with the envc web server, there is no user interaction between these two steps. The publish failure rate is typically less than 2% for states that haven't launched self-report. If a person has recently verified with a confirmed test and then later attempts to self report, that will count as a publish failure, since their previously published keys can't be downgraded from confirmed test to self report. 

There isn't any particular right value for the android publish share; it can vary by jurisdiction. But a sudden swing in either direction could mean a drop off in either number of iOS or Android devices publishing keys. 
