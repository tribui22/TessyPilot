/*
 * ================================================================================
 * TESSY INTERFACE INFORMATION - IcuHdl_TimerNoti_LowPulseMeasure
 * Generated: 2026-05-04 16:27:17
 * ================================================================================
 * 
 * EXTERNAL FUNCTIONS:
 * -------------------
 * unsigned char DioDrv_PinGet(unsigned char l_portidx_u8, unsigned char l_pinidx_u8)
 * void IrqHdl_IrqFlgClr(unsigned char locIrqIdx_u8)
 * void TauDrv_TimerDataGet(unsigned char l_moduleidx_u8, unsigned char l_channelidx_u8, unsigned short * l_val_u16ptr)
 * void inDetApplMeasCallBack(unsigned char channel_u8)
 * 
 * LOCAL FUNCTIONS:
 * ----------------
 * unsigned char IcuHdl_DigitGet(unsigned char Port, unsigned char Pin)
 * void IcuHdl_IrqFlgClr(unsigned char IrqIdx)
 * void IcuHdl_TimerDataGet(unsigned char ModuleIdx, unsigned char ChannelIdx, unsigned short * Val_ptr)
 * void IcuHdl_Task_InitMeasure(unsigned char locHdl_u8)
 * 
 * EXTERNAL VARIABLES:
 * -------------------
 * 
 * 
 * GLOBAL VARIABLES:
 * -----------------
 * unsigned char IcuHdl_MeasureTimeOutCnt_u8[3] [Passing: OUT] [ArrayLength: 3]
 * enum IcuHdl_MeasureState_t IcuHdl_MeasureState_en[3] [Passing: OUT] [ArrayLength: 3]
 * struct IcuHdl_PulseData_t IcuHdl_PulseData_st[3] [Passing: OUT] [ArrayLength: 3]
 *     unsigned short highPulse_u16 [Passing: OUT]
 *     unsigned short lowPulse_u16 [Passing: OUT]
 * struct IcuHdl_PulseData_t IcuHdl_PulseDataBak_st[3] [Passing: INOUT] [ArrayLength: 3]
 *     unsigned short highPulse_u16 [Passing: INOUT]
 *     unsigned short lowPulse_u16 [Passing: INOUT]
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

#define ICUHDL_PULSE_MAX 0xFFFFu
#define DioDrv_Level_High (0x01u)
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

typedef struct
{
    u16 highPulse_u16;
    u16 lowPulse_u16;
} IcuHdl_PulseData_t;


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