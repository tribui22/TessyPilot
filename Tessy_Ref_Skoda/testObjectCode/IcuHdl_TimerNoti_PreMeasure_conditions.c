void IcuHdl_TimerNoti_PreMeasure(u8 locHdl_u8)
{
if ((u8)X_IcuHdl_TauDrv_Sizeof > locHdl_u8) 
    {
        if (DioDrv_Level_Low == IcuHdl_DigitGet(IcuHdl_HwTauCfg_st[locHdl_u8].portIdx_u8, IcuHdl_HwTauCfg_st[locHdl_u8].pinIdx_u8))
        {
        }
        else
        {
        }
    }
}

