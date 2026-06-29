void IcuHdl_TimerNoti_LowPulseMeasure(u8 locHdl_u8)
{
if ((u8)X_IcuHdl_TauDrv_Sizeof > locHdl_u8) 
    {
        if (DioDrv_Level_High == IcuHdl_DigitGet(IcuHdl_HwTauCfg_st[locHdl_u8].portIdx_u8, IcuHdl_HwTauCfg_st[locHdl_u8].pinIdx_u8))
        {
            if (ICUHDL_PULSE_MAX != IcuHdl_PulseDataBak_st[locHdl_u8].lowPulse_u16)
            {
                IcuHdl_PulseDataBak_st[locHdl_u8].lowPulse_u16++;
            }
            if (0u != IcuHdl_PulseDataBak_st[locHdl_u8].highPulse_u16)
            {
            }
            else
            {
            }
        }
        else
        {
        }
    }
}

