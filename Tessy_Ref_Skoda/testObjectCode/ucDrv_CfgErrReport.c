void ucDrv_CfgErrReport(void) /* PRQA S 1532 # MD_WdgDrv_2E_Cfg_1532 */
{
    /* Declare a local variable lErrorNum_u8 of type u8 (unsigned 8-bit integer) and initialize it with the error code for a Configuration Register fault */
	u8 lErrorNum_u8 = (u8)BleM_ErrorCode_CLMSelfTestFail;

	/* Call the function BleM_ReportError with lErrorNum_u8 as the argument to report the error */
	BleM_ReportError(lErrorNum_u8);
}
