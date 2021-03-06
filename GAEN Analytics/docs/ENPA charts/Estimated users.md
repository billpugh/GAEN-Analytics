Shows an estimate of the total number of active ENX users (users running ENX for the region who are actively scanning for encounters). This estimate tends to be rather noisy, and we would expect that the actual count wouldn't change very quickly. Use a median value from the period when the case rates were high, and thus ENPA signal to noise ratio is highest. 

This uses both the ENPA and ENCV. It assumes that users who have enabled ENPA verify codes at the same rate as users who haven't verified codes. The calculation used is:


EPNA opt in = (# of ENPA users who verify codes)/(# of codes claimed on ENCV server)
Total users = (# of ENPA users)/(ENPA opt in)

These calculations can be very noisy when then the # of ENPA users who verify codes is close to the standard deviation. Thus, we only calculate the opt in rate when the number of ENPA users who verify codes is at 3 times the standard deviation, and the actual value for both ENPA opt-in and total users is the median of the last 14 days of reported values. 


