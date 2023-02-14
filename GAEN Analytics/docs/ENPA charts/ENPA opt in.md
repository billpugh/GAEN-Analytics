Shows a percentage of the number of ENX users that are using ENPA. 

There are two ways to calculate this. One is to use the region's data from ENPA and ENCV, and compare the number of people who verify a code according to ENPA with total number of people who verify a code (according to ENCV). This calculation can be very noisy when then the # of ENPA users who verify codes is close to the standard deviation. Thus, we only calculate the opt in rate when the number of ENPA users who verify codes is at 3 times the standard deviation.  The calculaton used is:

EPNA opt in = (# of ENPA users who verify codes)/(# of codes claimed on ENCV server)

Note that when calculating seperate opt-in values for Android and iOS platforms, we use the number of users sharing keys rather than verifying codes, because only that data is available by platform from the ENCV server. 

We can also compare the total number of ENPA users in the United States with the total number of users of the US National key server (aka ENCV). We have to adjust this for the fact that the US states offering ENX with ENPA have 70% of the population of all US states using EN. This number started around 35%, increasing to 45% by April 2022. 

Using the regional data tends to be noisy, particularly when the signal to noise ratio for people who verify codes is low. Also, they reflect the ENPA adoption rate in two different populations: particularly now that users can self-report, the users who verify codes may not be as representative of the entire population of people who have ENX active on their phones. 

Because of the noise in the regional data, the number shown is the median value from the past 14 days.

Although the regional calculation incorporates regional differences, I recommend that regions simply use the US ENPA % as the best estimate of ENPA opt-in in their region. The noise in the regional calculation and the fact that it is measuring a different population than all ENPA users make it a less reliable measurement. It continues to be displayed in the tool because it is the metric that was historically reported by GAEN Analyzer. 


