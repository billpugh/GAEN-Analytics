iOS ENPA data

This provides combined ENPA data for just iOS devices. Most of the numbers from individual metrics are rates per 100K reporting devices (including standard deviation). 

There was an error in the iOS implementation of ENPA that was fixed in iOS 14.6; due to this bug, a proportion of iOS devices were reporting ENPA data, but were not actually recording any events (such as getting a notification or verifying a code). Fortunately, from one of the metrics were are able to calculate an estimate of the number of devices that are not reporting events, and that is used to compute a scaling factor, which has been applied. The scaling factor is one of the columns in the chart. Because some devices don't get updated to newer versions, there are still a few devices effected by this bug, so the scaling factor is still slightly above 1.  

[definitions of computed metrics here](https://docs.google.com/spreadsheets/d/1FalTR8Q9He-Axjx09yic-PGgy4analJVQiXi1HWHkuA/edit?usp=sharing)

