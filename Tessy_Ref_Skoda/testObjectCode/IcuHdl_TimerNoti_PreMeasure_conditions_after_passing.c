/*
 * ================================================================================
 * TESSY INTERFACE INFORMATION - IcuHdl_TimerNoti_PreMeasure
 * Generated: 2026-05-04 13:48:55
 * ================================================================================
 * 
 * EXTERNAL FUNCTIONS:
 * -------------------
 * unsigned char DioDrv_PinGet(unsigned char l_portidx_u8, unsigned char l_pinidx_u8)
 * 
 * LOCAL FUNCTIONS:
 * ----------------
 * unsigned char IcuHdl_DigitGet(unsigned char Port, unsigned char Pin)
 * 
 * EXTERNAL VARIABLES:
 * -------------------
 * 
 * 
 * GLOBAL VARIABLES:
 * -----------------
 * unsigned char IcuHdl_MeasureTimeOutCnt_u8[3] [Passing: OUT] [ArrayLength: 3]
 * enum IcuHdl_MeasureState_t IcuHdl_MeasureState_en[3] [Passing: OUT] [ArrayLength: 3]
 * 
 * PARAMETERS:
 * -----------
 * unsigned char locHdl_u8 [Passing: IN]
 * 
 * RETURN TYPE:
 * ------------
 * 
 * ================================================================================
 * 
 */

#define DioDrv_Level_Low (0x00u)
#define IcuHdl_PWM_IN_WEL_PWM  0
#define IcuHdl_FAULT1_TLD6098  1
#define IcuHdl_FAULT2_TLD6098  2
#define X_IcuHdl_TauDrv_Sizeof  3


typedef enum 
{
    IcuHdl_InitMeasure = 0u, 
    IcuHdl_PreMeasure = 1u, 
    IcuHdl_HighPulseMeasure = 2u, 
    IcuHdl_LowPulseMeasure = 3u 
} IcuHdl_MeasureState_t;


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