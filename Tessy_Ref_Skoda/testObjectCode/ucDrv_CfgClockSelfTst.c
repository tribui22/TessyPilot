ucDrv_ClkSelfTst_sts_t ucDrv_CfgClockSelfTst(const ucDrv_Cfg_ClkSelfTst_t * config_ptr)
{
    ucDrv_ClkSelfTst_sts_t retval_en = ucDrv_ClkSelfTst_Pass;
    u32 ucDrv_Cfg_FccCount_u32 = 0u;
    u32 ucDrv_Cfg_FccFrequency_u32 = 0u;
    u32 ucDrv_Cfg_FccFreqTempUp_u32 = 0u;
    u32 ucDrv_Cfg_FccFreqTempDown_u32 = 0u;
    u32 l_Timeout_u32 = config_ptr->testTimeOut;
    ucDrv_UnlockRegister();
    /* Configure FCC */
    ucDrv_ConfigureFCC((ucDrv_Cfg_ClkSelfTst_t *) config_ptr);

    /* Set FCC counting periods */
    ucDrv_SetFCCPeriod((ucDrv_Cfg_ClkSelfTst_t *) config_ptr);

    /* Start the measurement */
    ucDrv_StartFCC();
    ucDrv_UnlockRegister();
    /* Wait for completion */
    while ((ucDrv_FCCDone() == FALSE)&&(l_Timeout_u32 > 0u))
    {
        l_Timeout_u32--;
    }

    /* Read the counter value */
    ucDrv_Cfg_FccCount_u32 = ucDrv_ReadFCC();
    
    /* Calculate frequency */
    ucDrv_Cfg_FccFrequency_u32 = (ucDrv_Cfg_FccCount_u32 * UCDRV_CFG_SYSCTL_FCC_TRIGSRC_FREQ_REF) / (config_ptr->fccCountingPeriods_u8 + 1u);  /* Result in Hz */
    ucDrv_Cfg_FccFreqTempUp_u32 = config_ptr->expectedFrequency_en + ((config_ptr->expectedFrequency_en * config_ptr->tolerance_u8) / 100u);
    ucDrv_Cfg_FccFreqTempDown_u32 = config_ptr->expectedFrequency_en - ((config_ptr->expectedFrequency_en * config_ptr->tolerance_u8) / 100u);
    /* Determine self-test status */
    if (ucDrv_Cfg_FccFrequency_u32 > ucDrv_Cfg_FccFreqTempUp_u32)
    {
        retval_en = ucDrv_ClkSelfTst_OvFrq;
    }
    else if (ucDrv_Cfg_FccFrequency_u32 < ucDrv_Cfg_FccFreqTempDown_u32)
    {
        retval_en = ucDrv_ClkSelfTst_UnderFrq;
    }
    else
    {
        retval_en = ucDrv_ClkSelfTst_Pass;
    }
    return retval_en;
}
