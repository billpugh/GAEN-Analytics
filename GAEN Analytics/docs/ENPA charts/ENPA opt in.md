Shows a percentage of the number of ENX users that are using ENPA. This estimate tends to be rather noisy, and we would expect that the actual count wouldn't change very quickly. Use a median value from the period when the case rates were high, and thus ENPA signal to noise ratio is highest. 

This uses both the ENPA and ENCV. It assumes that users who have enabled ENPA verify codes at the same rate as users who haven't verified codes. The calculation used is

EPNA opt in = (# of ENPA users who verify codes)/(# of codes claimed on ENCV server)
