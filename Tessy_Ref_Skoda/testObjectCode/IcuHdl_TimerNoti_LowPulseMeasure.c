void IcuHdl_TimerNoti_LowPulseMeasure(u8 locHdl_u8)
{
    if ((u8)X_IcuHdl_TauDrv_Sizeof > locHdl_u8) /* Polyspace RTE:UNR [Justified:Low] "Condition statement always true depend on specified project configuration" */
    {
        if (DioDrv_Level_High == IcuHdl_DigitGet(IcuHdl_HwTauCfg_st[locHdl_u8].portIdx_u8, IcuHdl_HwTauCfg_st[locHdl_u8].pinIdx_u8))
        {
            /* get capture timer value */
            IcuHdl_TimerDataGet(IcuHdl_HwTauCfg_st[locHdl_u8].timerModuleIdx_u8, IcuHdl_HwTauCfg_st[locHdl_u8].timerChannelIdx_u8, &(IcuHdl_PulseDataBak_st[locHdl_u8].lowPulse_u16));
            /* actual value = capture timer value + 1 */
            if (ICUHDL_PULSE_MAX != IcuHdl_PulseDataBak_st[locHdl_u8].lowPulse_u16)
            {
                IcuHdl_PulseDataBak_st[locHdl_u8].lowPulse_u16++;
            }
            /* check if measurement complete */
            if (0u != IcuHdl_PulseDataBak_st[locHdl_u8].highPulse_u16)
            {
                /* data copy */
                IcuHdl_PulseData_st[locHdl_u8].highPulse_u16 = IcuHdl_PulseDataBak_st[locHdl_u8].highPulse_u16;
                IcuHdl_PulseData_st[locHdl_u8].lowPulse_u16 = IcuHdl_PulseDataBak_st[locHdl_u8].lowPulse_u16;
                /* calling measurement call back to measure low pulse */
                Rte_Call_InDetAppl_MeasCallBack((u8)locHdl_u8);
                /* back buffer init */
                IcuHdl_PulseDataBak_st[locHdl_u8].highPulse_u16 = ICUHDL_PULSE_MIN;
                IcuHdl_PulseDataBak_st[locHdl_u8].lowPulse_u16 = ICUHDL_PULSE_MIN;
                /* state transmit */
                IcuHdl_MeasureState_en[locHdl_u8] = IcuHdl_HighPulseMeasure;
                /* reset timeout counter */
                IcuHdl_MeasureTimeOutCnt_u8[locHdl_u8] = IcuHdl_HwTauCfg_st[locHdl_u8].timeOutCnt;
            }
            else
            {
                /* start next measurement */
                IcuHdl_MeasureState_en[locHdl_u8] = IcuHdl_HighPulseMeasure;
                /* reset timeout counter */
                IcuHdl_MeasureTimeOutCnt_u8[locHdl_u8] = IcuHdl_HwTauCfg_st[locHdl_u8].timeOutCnt;
            }
        }
        else
        {
            /* initialize measurement */
            IcuHdl_Task_InitMeasure(locHdl_u8);
        }
    }
}
