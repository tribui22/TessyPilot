ucDrv_ClkSelfTst_sts_t ucDrv_CfgClockSelfTst(const ucDrv_Cfg_ClkSelfTst_t * config_ptr)
{
u32 ucDrv_Cfg_FccFrequency_u32 = 0u;
    u32 ucDrv_Cfg_FccFreqTempUp_u32 = 0u;
    u32 ucDrv_Cfg_FccFreqTempDown_u32 = 0u;

    while ((ucDrv_FCCDone() == FALSE)&&(l_Timeout_u32 > 0u))
    {
    }

    ucDrv_Cfg_FccFrequency_u32 = (ucDrv_Cfg_FccCount_u32 * UCDRV_CFG_SYSCTL_FCC_TRIGSRC_FREQ_REF) / (config_ptr->fccCountingPeriods_u8 + 1u);  /* Result in Hz */
    ucDrv_Cfg_FccFreqTempUp_u32 = config_ptr->expectedFrequency_en + ((config_ptr->expectedFrequency_en * config_ptr->tolerance_u8) / 100u);
    ucDrv_Cfg_FccFreqTempDown_u32 = config_ptr->expectedFrequency_en - ((config_ptr->expectedFrequency_en * config_ptr->tolerance_u8) / 100u);
    if (ucDrv_Cfg_FccFrequency_u32 > ucDrv_Cfg_FccFreqTempUp_u32)
    {
    }
    else if (ucDrv_Cfg_FccFrequency_u32 < ucDrv_Cfg_FccFreqTempDown_u32)
    {
    }
    else
    {
    }
}

